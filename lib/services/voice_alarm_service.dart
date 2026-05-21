import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCaptureException implements Exception {
  const VoiceCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VoiceAlarmDraft {
  const VoiceAlarmDraft({
    required this.alarmName,
    required this.location,
    this.radiusMeters = 100,
    this.transcript,
  });

  final String alarmName;
  final String location;
  final double radiusMeters;
  final String? transcript;
}

class VoiceAlarmService {
  VoiceAlarmService({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  static const Duration defaultListenFor = Duration(seconds: 5);
  static const Duration defaultPauseFor = Duration(milliseconds: 1300);
  static const List<String> _supportedLocales = ['en_GB', 'es_ES'];

  Future<String?> listenOnce({
    String? localeId,
    Duration listenFor = defaultListenFor,
    Duration pauseFor = defaultPauseFor,
    void Function(String transcript)? onTranscriptChanged,
  }) async {
    bool available;
    try {
      available = await _speech.initialize();
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
    String heard = '';

    Future<void> finish({bool cancelIfSilent = false}) async {
      if (_speech.isListening) {
        if (cancelIfSilent && heard.trim().isEmpty) {
          await _speech.cancel();
        } else {
          await _speech.stop();
        }
      }
      if (!completer.isCompleted) {
        final text = heard.trim();
        completer.complete(text.isEmpty ? null : text);
      }
    }

    try {
      await _speech.listen(
        localeId: resolvedLocaleId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
        onResult: (result) {
          heard = result.recognizedWords;
          onTranscriptChanged?.call(heard.trim());
          if (result.finalResult) {
            finish();
          }
        },
        onSoundLevelChange: (_) {},
      );
    } on PlatformException catch (e) {
      throw VoiceCaptureException(
        e.message ?? 'Voice capture failed while listening.',
      );
    }

    Future<void>.delayed(
      listenFor + const Duration(milliseconds: 250),
      () => finish(cancelIfSilent: true),
    );
    return completer.future;
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
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
      radiusMeters: radius,
      transcript: cleanedTranscript,
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
