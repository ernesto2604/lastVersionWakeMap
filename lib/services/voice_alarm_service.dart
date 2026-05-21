import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../config/app_config.dart';

class VoiceCaptureException implements Exception {
  const VoiceCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VoiceAlarmParseException implements Exception {
  const VoiceAlarmParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VoiceAlarmDraft {
  const VoiceAlarmDraft({
    required this.alarmName,
    required String location,
    String? displayLocation,
    String? geocodingQuery,
    this.radiusMeters = 100,
    this.transcript,
    this.confidence = 'medium',
    this.missingFields = const [],
  }) : location = displayLocation ?? location,
       displayLocation = displayLocation ?? location,
       geocodingQuery = geocodingQuery ?? displayLocation ?? location;

  final String alarmName;
  final String location;
  final String displayLocation;
  final String geocodingQuery;
  final double radiusMeters;
  final String? transcript;
  final String confidence;
  final List<String> missingFields;

  factory VoiceAlarmDraft.fromJson(
    Map<String, dynamic> json, {
    String? transcript,
  }) {
    final alarmName = _requiredTrimmedString(json['alarmName'], 'alarmName');
    final displayLocation = _requiredTrimmedString(
      json['displayLocation'],
      'displayLocation',
    );
    final geocodingQuery = _requiredTrimmedString(
      json['geocodingQuery'],
      'geocodingQuery',
    );
    final radius = _parseRadius(json['radiusMeters']);
    final confidence = _parseConfidence(json['confidence']);
    final missingFields = _parseMissingFields(json['missingFields']);

    return VoiceAlarmDraft(
      alarmName: alarmName,
      location: displayLocation,
      displayLocation: displayLocation,
      geocodingQuery: geocodingQuery,
      radiusMeters: radius,
      transcript: transcript,
      confidence: confidence,
      missingFields: missingFields,
    );
  }

  List<String> geocodingQueries() {
    final queries = <String>[];

    void add(String value) {
      final trimmed = _normalizeSpacesStatic(value);
      if (trimmed.isEmpty) return;
      final exists = queries.any(
        (item) => item.toLowerCase() == trimmed.toLowerCase(),
      );
      if (!exists) queries.add(trimmed);
    }

    add(displayLocation);
    add(geocodingQuery);

    final stationCity =
        _extractStationCity(displayLocation) ??
        _extractStationCity(geocodingQuery);
    if (stationCity != null) {
      add('$stationCity Station, $stationCity, UK');
      add('$stationCity train station, UK');
      add('$stationCity railway station, UK');
      add('$stationCity Station');
    }

    add(_withoutCountrySuffix(displayLocation));
    add(_withoutCountrySuffix(geocodingQuery));

    return queries;
  }

  static String _requiredTrimmedString(Object? value, String fieldName) {
    if (value is! String || value.trim().isEmpty) {
      throw VoiceAlarmParseException(
        'Voice parser returned an invalid "$fieldName" value.',
      );
    }
    return _normalizeSpacesStatic(value);
  }

  static double _parseRadius(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) {
      throw const VoiceAlarmParseException(
        'Voice parser returned an invalid radius.',
      );
    }
    return number.clamp(100, 1000).toDouble();
  }

  static String _parseConfidence(Object? value) {
    if (value is! String) return 'low';
    final normalized = value.trim().toLowerCase();
    return const {'high', 'medium', 'low'}.contains(normalized)
        ? normalized
        : 'low';
  }

  static List<String> _parseMissingFields(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map(_normalizeSpacesStatic)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static String _normalizeSpacesStatic(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _extractStationCity(String value) {
    final firstPart = value.split(',').first.trim();
    if (firstPart.isEmpty) return null;

    final stationMatch = RegExp(
      r'^(.+?)\s+(?:train\s+station|railway\s+station|station)$',
      caseSensitive: false,
    ).firstMatch(firstPart);
    if (stationMatch == null) return null;

    final city = _normalizeSpacesStatic(stationMatch.group(1) ?? '');
    return city.isEmpty ? null : city;
  }

  static String _withoutCountrySuffix(String value) {
    var output = _normalizeSpacesStatic(value);
    output = output.replaceFirst(
      RegExp(r',?\s*(?:uk|united kingdom)$', caseSensitive: false),
      '',
    );
    return _normalizeSpacesStatic(output);
  }
}

class VoiceAlarmService {
  VoiceAlarmService({SpeechToText? speech, http.Client? httpClient})
    : _speech = speech ?? SpeechToText(),
      _httpClient = httpClient ?? http.Client();

  final SpeechToText _speech;
  final http.Client _httpClient;
  static const Duration defaultListenFor = Duration(seconds: 12);
  static const Duration defaultPauseFor = Duration(milliseconds: 2800);
  static const Duration _parseTimeout = Duration(seconds: 15);
  static const List<String> _supportedLocales = ['en_GB', 'es_ES'];
  static const Duration _finalResultGrace = Duration(milliseconds: 700);
  static const Duration _silentFinishGrace = Duration(milliseconds: 250);
  static const Duration _hardTimeoutPadding = Duration(milliseconds: 750);

  Completer<String?>? _activeCompleter;
  Timer? _finishTimer;
  String _heard = '';
  bool _isFinishing = false;

  Future<String?> listenOnce({
    String? localeId,
    Duration listenFor = defaultListenFor,
    Duration pauseFor = defaultPauseFor,
    void Function(String transcript)? onTranscriptChanged,
  }) async {
    bool available;
    try {
      available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
    } on MissingPluginException {
      throw const VoiceCaptureException(
        'Voice plugin not loaded. Fully restart the app (stop and run again).',
      );
    } on PlatformException catch (e) {
      throw VoiceCaptureException(
        e.message ?? 'Voice initialization failed on this device.',
      );
    }

    if (!available) {
      throw const VoiceCaptureException(
        'Speech recognition is unavailable or permission was denied.',
      );
    }

    final resolvedLocaleId = await _resolveLocale(localeId);
    final completer = Completer<String?>();
    _activeCompleter = completer;
    _heard = '';
    _isFinishing = false;
    _finishTimer?.cancel();

    try {
      await _speech.listen(
        localeId: resolvedLocaleId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
        ),
        onResult: (result) {
          _heard = _moreCompleteTranscript(
            current: _heard,
            incoming: result.recognizedWords,
            isFinal: result.finalResult,
          );
          onTranscriptChanged?.call(_heard.trim());
          if (result.finalResult) {
            _scheduleFinish(_finalResultGrace);
          }
        },
        onSoundLevelChange: (_) {},
      );
    } on PlatformException catch (e) {
      _activeCompleter = null;
      _heard = '';
      _isFinishing = false;
      _finishTimer?.cancel();
      _finishTimer = null;
      throw VoiceCaptureException(
        e.message ?? 'Voice capture failed while listening.',
      );
    }

    Future<void>.delayed(
      listenFor + _hardTimeoutPadding,
      () => _finishActiveCapture(cancelIfSilent: true),
    );
    return completer.future;
  }

  Future<void> cancel() async {
    _finishTimer?.cancel();
    _finishTimer = null;
    final completer = _activeCompleter;
    _activeCompleter = null;
    _heard = '';
    _isFinishing = false;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  Future<VoiceAlarmDraft> parseAlarmDraftWithAi(String transcript) async {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      throw const VoiceAlarmParseException('Voice transcript is empty.');
    }

    final uri = _buildBackendUri('/api/parse-voice-alarm');
    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'transcript': trimmed}),
          )
          .timeout(_parseTimeout);
    } catch (_) {
      throw const VoiceAlarmParseException(
        'Voice parser is unavailable. Review the fields manually.',
      );
    }

    final decoded = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceAlarmParseException(
        _extractBackendError(decoded) ??
            'Voice parser failed. Review the fields manually.',
      );
    }

    if (decoded == null) {
      throw const VoiceAlarmParseException(
        'Voice parser returned malformed data. Review the fields manually.',
      );
    }

    return VoiceAlarmDraft.fromJson(decoded, transcript: trimmed);
  }

  VoiceAlarmDraft parseAlarmDraft(String transcript) {
    final cleanedTranscript = _normalizeSpaces(transcript);

    // --- 1. Extract radius (e.g. "300 metres", "radius of 200", "within 500 m") ---
    double radius = 300; // sensible default (midpoint of 100–1000 slider)
    String working = cleanedTranscript;

    final radiusPatterns = <RegExp>[
      // "radius of 300 metres" / "radius of 300"
      RegExp(
        r'(?:with\s+)?(?:a\s+)?radius\s+of\s+(\d+)\s*(?:met(?:re|er)s?|m\b)?',
        caseSensitive: false,
      ),
      // "radio de 300 metros" / "en un radio de 300"
      RegExp(
        r'(?:con\s+)?(?:un\s+)?radio\s+de\s+(\d+)\s*(?:metros?|m\b)?',
        caseSensitive: false,
      ),
      // "300 metre radius" / "300 m radius"
      RegExp(r'(\d+)\s*(?:met(?:re|er)s?|m)\s+radius', caseSensitive: false),
      // "300 metros de radio"
      RegExp(r'(\d+)\s*(?:metros?|m)\s+de\s+radio', caseSensitive: false),
      // "at 500 metres" / "at 500 m" (end of sentence)
      RegExp(r'\bat\s+(\d+)\s*(?:met(?:re|er)s?|m)\s*$', caseSensitive: false),
      // "a 500 metros" / "en 500 metros"
      RegExp(r'\b(?:a|en)\s+(\d+)\s*(?:metros?|m)\s*$', caseSensitive: false),
      // "within 400 metres"
      RegExp(r'within\s+(\d+)\s*(?:met(?:re|er)s?|m\b)?', caseSensitive: false),
      // "dentro de 400 metros"
      RegExp(r'dentro\s+de\s+(\d+)\s*(?:metros?|m\b)?', caseSensitive: false),
      // standalone "300 metres" / "300 m" not already matched
      RegExp(r'(\d+)\s*(?:met(?:re|er)s?|metros?|m)\b', caseSensitive: false),
    ];

    for (final pattern in radiusPatterns) {
      final match = pattern.firstMatch(working);
      if (match != null) {
        final parsed = double.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > 0) {
          radius = parsed.clamp(100, 1000);
          // Remove the matched radius phrase from the working text
          working = working.replaceFirst(match.group(0)!, '').trim();
          working = _normalizeSpaces(working);
        }
        break;
      }
    }

    // --- 2. Extract explicit alarm name ("called X", "named X") ---
    String? explicitName;
    final namePatterns = <RegExp>[
      // "called University for ..." — name is between "called" and "for"
      RegExp(r'\bcalled\s+(.+?)(?=\s+for\s+)', caseSensitive: false),
      // "named University for ..."
      RegExp(r'\bnamed\s+(.+?)(?=\s+for\s+)', caseSensitive: false),
      // "llamada Universidad para/en/a ..."
      RegExp(
        r'\bllamad[ao]\s+(.+?)(?=\s+(?:para|en|a)\s+)',
        caseSensitive: false,
      ),
      // "con nombre Universidad para/en/a ..."
      RegExp(
        r'\bcon\s+nombre\s+(.+?)(?=\s+(?:para|en|a)\s+)',
        caseSensitive: false,
      ),
      // "called University" at end
      RegExp(r'\bcalled\s+(.+)', caseSensitive: false),
      // "named University" at end
      RegExp(r'\bnamed\s+(.+)', caseSensitive: false),
      // "llamada Universidad" at end
      RegExp(r'\bllamad[ao]\s+(.+)', caseSensitive: false),
      // "con nombre Universidad" at end
      RegExp(r'\bcon\s+nombre\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(working);
      if (match != null) {
        final candidate = (match.group(1) ?? '').trim();
        if (candidate.isNotEmpty) {
          explicitName = _toTitleCase(_cleanLocation(candidate));
          // Remove the "called/named X" fragment so it doesn't pollute location
          working = working.replaceFirst(match.group(0)!, '').trim();
          working = _normalizeSpaces(working);
        }
        break;
      }
    }

    // --- 3. Extract location from remaining text ---
    String location = '';
    final locationPatterns = <RegExp>[
      RegExp(r'when\s+i\s+arrive\s+(?:to|at|in)\s+(.+)', caseSensitive: false),
      RegExp(r'when\s+i\s+get\s+to\s+(.+)', caseSensitive: false),
      RegExp(r'when\s+i\s+reach\s+(.+)', caseSensitive: false),
      RegExp(
        r'(?:arrive|reach|get)\s+(?:to|at|in)\s+(.+)',
        caseSensitive: false,
      ),
      RegExp(
        r'cuando\s+llegue\s+(?:a|al|a\s+la|a\s+el|en)\s+(.+)',
        caseSensitive: false,
      ),
      RegExp(
        r'cuando\s+llego\s+(?:a|al|a\s+la|a\s+el|en)\s+(.+)',
        caseSensitive: false,
      ),
      RegExp(
        r'al\s+llegar\s+(?:a|al|a\s+la|a\s+el|en)\s+(.+)',
        caseSensitive: false,
      ),
      RegExp(r'cuando\s+est[eé]\s+en\s+(.+)', caseSensitive: false),
      RegExp(
        r'(?:llegue|llego|llegar)\s+(?:a|al|a\s+la|a\s+el|en)\s+(.+)',
        caseSensitive: false,
      ),
      RegExp(r'\bnear\s+(.+)', caseSensitive: false),
      RegExp(r'\bfor\s+(.+)', caseSensitive: false),
      RegExp(r'\bpara\s+(.+)', caseSensitive: false),
      RegExp(r'\bto\s+(.+)', caseSensitive: false),
      RegExp(r'\bat\s+(.+)', caseSensitive: false),
      RegExp(r'\bin\s+(.+)', caseSensitive: false),
      RegExp(r'\ben\s+(.+)', caseSensitive: false),
      RegExp(r'\ba\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in locationPatterns) {
      final match = pattern.firstMatch(working);
      if (match != null && match.groupCount >= 1) {
        location = (match.group(1) ?? '').trim();
        if (location.isNotEmpty) break;
      }
    }

    if (location.isEmpty) {
      location = working
          .replaceFirst(
            RegExp(
              r'^(?:put|set|create)\s+(?:an?\s+)?alarm\s*',
              caseSensitive: false,
            ),
            '',
          )
          .replaceFirst(RegExp(r'^(?:wake\s+me)\s*', caseSensitive: false), '')
          .replaceFirst(
            RegExp(
              r'^(?:pon|ponme|crea|crear|activa)\s+(?:una\s+)?alarma\s*',
              caseSensitive: false,
            ),
            '',
          )
          .replaceFirst(
            RegExp(r'^(?:av[ií]same|despi[eé]rtame)\s*', caseSensitive: false),
            '',
          )
          .trim();
    }

    location = _cleanLocation(location);

    // --- 4. Determine alarm name ---
    String alarmName;
    if (explicitName != null && explicitName.isNotEmpty) {
      alarmName = explicitName;
    } else if (location.isEmpty) {
      alarmName = cleanedTranscript.toLowerCase().contains('home')
          ? 'Home Alarm'
          : cleanedTranscript.toLowerCase().contains('casa')
          ? 'Alarma Casa'
          : 'Voice Alarm';
      location = cleanedTranscript;
    } else {
      final firstChunk = location.split(',').first.trim();
      alarmName = firstChunk.isEmpty ? 'Voice Alarm' : _toTitleCase(firstChunk);
    }

    return VoiceAlarmDraft(
      alarmName: alarmName,
      location: location,
      geocodingQuery: location,
      radiusMeters: radius,
      transcript: cleanedTranscript,
      confidence: 'low',
    );
  }

  String _normalizeSpaces(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String> _resolveLocale(String? requestedLocaleId) async {
    String normalize(String value) => value.replaceAll('-', '_');

    final locales = await _speech.locales();
    final availableIds = locales
        .map((locale) => normalize(locale.localeId))
        .toSet();

    String? findAvailable(String target) {
      final normalizedTarget = normalize(target);
      if (availableIds.contains(normalizedTarget)) return normalizedTarget;

      final languageCode = normalizedTarget.split('_').first;
      for (final localeId in _supportedLocales) {
        if (localeId.startsWith(languageCode) &&
            availableIds.contains(localeId)) {
          return localeId;
        }
      }
      return null;
    }

    if (requestedLocaleId != null && requestedLocaleId.trim().isNotEmpty) {
      final requested = normalize(requestedLocaleId.trim());
      if (_supportedLocales.contains(requested)) {
        final resolved = findAvailable(requested);
        if (resolved != null) return resolved;
      }
    }

    final deviceLocale = PlatformDispatcher.instance.locale;
    final preferredByDevice = deviceLocale.languageCode == 'es'
        ? 'es_ES'
        : 'en_GB';

    final deviceMatch = findAvailable(preferredByDevice);
    if (deviceMatch != null) return deviceMatch;

    for (final localeId in _supportedLocales) {
      final match = findAvailable(localeId);
      if (match != null) return match;
    }

    throw const VoiceCaptureException(
      'Voice input supports only UK English and Spain Spanish on this device.',
    );
  }

  Uri _buildBackendUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const VoiceAlarmParseException(
        'Voice parser backend is not configured.',
      );
    }

    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, dynamic>? _decodeJsonObject(String rawBody) {
    if (rawBody.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawBody);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _extractBackendError(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final error = payload['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    return null;
  }

  void _handleSpeechStatus(String status) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) return;

    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      final heardSpeech = _heard.trim().isNotEmpty;
      _scheduleFinish(
        heardSpeech ? _finalResultGrace : _silentFinishGrace,
        cancelIfSilent: !heardSpeech,
      );
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) return;

    if (_heard.trim().isNotEmpty) {
      _scheduleFinish(_finalResultGrace);
      return;
    }

    if (_isNoSpeechError(error.errorMsg)) {
      _scheduleFinish(_silentFinishGrace, cancelIfSilent: true);
      return;
    }

    _finishTimer?.cancel();
    _finishTimer = null;
    _activeCompleter = null;
    _heard = '';
    _isFinishing = false;
    if (_speech.isListening) {
      unawaited(_speech.cancel());
    }
    completer.completeError(
      const VoiceCaptureException(
        'Voice capture stopped unexpectedly. Please try again.',
      ),
    );
  }

  bool _isNoSpeechError(String errorMsg) {
    final normalized = errorMsg.toLowerCase();
    return normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('no speech') ||
        normalized.contains('timeout');
  }

  void _scheduleFinish(Duration delay, {bool cancelIfSilent = false}) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) return;

    _finishTimer?.cancel();
    _finishTimer = Timer(
      delay,
      () => unawaited(_finishActiveCapture(cancelIfSilent: cancelIfSilent)),
    );
  }

  Future<void> _finishActiveCapture({bool cancelIfSilent = false}) async {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted || _isFinishing) return;

    _isFinishing = true;
    _finishTimer?.cancel();
    _finishTimer = null;

    if (_speech.isListening) {
      if (cancelIfSilent && _heard.trim().isEmpty) {
        await _speech.cancel();
      } else {
        await _speech.stop();
      }
    }

    final text = _heard.trim();
    if (!completer.isCompleted) {
      completer.complete(text.isEmpty ? null : text);
    }

    _activeCompleter = null;
    _heard = '';
    _isFinishing = false;
  }

  String _moreCompleteTranscript({
    required String current,
    required String incoming,
    required bool isFinal,
  }) {
    final currentText = _normalizeSpaces(current);
    final incomingText = _normalizeSpaces(incoming);
    if (incomingText.isEmpty) return currentText;
    if (currentText.isEmpty) return incomingText;
    if (incomingText == currentText) return incomingText;

    final currentLower = currentText.toLowerCase();
    final incomingLower = incomingText.toLowerCase();
    if (incomingLower.contains(currentLower)) return incomingText;
    if (currentLower.contains(incomingLower)) {
      final keepsMostWords = incomingText.length >= currentText.length * 0.95;
      return isFinal && keepsMostWords ? incomingText : currentText;
    }

    if (isFinal && incomingText.length >= currentText.length * 0.75) {
      return incomingText;
    }

    return incomingText.length > currentText.length
        ? incomingText
        : currentText;
  }

  String _cleanLocation(String input) {
    var output = input.trim();
    output = output.replaceAll(RegExp(r'^[,.;:!\-\s]+'), '');
    output = _trimTrailingPunctuation(output);
    output = output.replaceFirst(
      RegExp(r'^(the)\s+', caseSensitive: false),
      '',
    );
    return output.trim();
  }

  String _trimTrailingPunctuation(String input) {
    var value = input;
    const trailing = ',.;:!- ';
    while (value.isNotEmpty && trailing.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String _toTitleCase(String input) {
    final words = input.split(RegExp(r'\s+'));
    return words
        .where((w) => w.isNotEmpty)
        .map((word) {
          if (word.length == 1) return word.toUpperCase();
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }
}
