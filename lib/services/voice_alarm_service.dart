import 'dart:async';

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
  VoiceAlarmService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  Future<String?> listenOnce({
    String localeId = 'en_US',
    Duration listenFor = const Duration(minutes: 2),
    Duration pauseFor = const Duration(seconds: 2),
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

    final completer = Completer<String?>();
    String heard = '';

    Future<void> finish() async {
      if (_speech.isListening) {
        await _speech.stop();
      }
      if (!completer.isCompleted) {
        final text = heard.trim();
        completer.complete(text.isEmpty ? null : text);
      }
    }

    try {
      await _speech.listen(
        localeId: localeId,
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

    Future<void>.delayed(listenFor + const Duration(milliseconds: 600), finish);
    return completer.future;
  }

  VoiceAlarmDraft parseAlarmDraft(String transcript) {
    final cleanedTranscript = _normalizeSpaces(transcript);

    // --- 1. Extract radius (e.g. "300 metres", "radius of 200", "within 500 m") ---
    double radius = 300; // sensible default (midpoint of 100–1000 slider)
    String working = cleanedTranscript;

    final radiusPatterns = <RegExp>[
      // "radius of 300 metres" / "radius of 300"
      RegExp(r'(?:with\s+)?(?:a\s+)?radius\s+of\s+(\d+)\s*(?:met(?:re|er)s?|m\b)?', caseSensitive: false),
      // "300 metre radius" / "300 m radius"
      RegExp(r'(\d+)\s*(?:met(?:re|er)s?|m)\s+radius', caseSensitive: false),
      // "at 500 metres" / "at 500 m" (end of sentence)
      RegExp(r'\bat\s+(\d+)\s*(?:met(?:re|er)s?|m)\s*$', caseSensitive: false),
      // "within 400 metres"
      RegExp(r'within\s+(\d+)\s*(?:met(?:re|er)s?|m\b)?', caseSensitive: false),
      // standalone "300 metres" / "300 m" not already matched
      RegExp(r'(\d+)\s*(?:met(?:re|er)s?|m)\b', caseSensitive: false),
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
      RegExp(r'\bcalled\s+(.+?)\s+for\s+', caseSensitive: false),
      // "named University for ..."
      RegExp(r'\bnamed\s+(.+?)\s+for\s+', caseSensitive: false),
      // "called University" at end
      RegExp(r'\bcalled\s+(.+)', caseSensitive: false),
      // "named University" at end
      RegExp(r'\bnamed\s+(.+)', caseSensitive: false),
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
          // If we matched "called X for ..." we removed "for" too, re-add context
          if (pattern.pattern.contains(r'for\s+')) {
            // The text after "for" is still in working — nothing to restore
          }
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
      RegExp(r'(?:arrive|reach|get)\s+(?:to|at|in)\s+(.+)', caseSensitive: false),
      RegExp(r'\bnear\s+(.+)', caseSensitive: false),
      RegExp(r'\bfor\s+(.+)', caseSensitive: false),
      RegExp(r'\bto\s+(.+)', caseSensitive: false),
      RegExp(r'\bat\s+(.+)', caseSensitive: false),
      RegExp(r'\bin\s+(.+)', caseSensitive: false),
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
          .replaceFirst(RegExp(r'^(?:put|set|create)\s+(?:an?\s+)?alarm\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^(?:wake\s+me)\s*', caseSensitive: false), '')
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

  String _cleanLocation(String input) {
    var output = input.trim();
    output = output.replaceAll(RegExp(r'^[,.;:!\-\s]+'), '');
    output = _trimTrailingPunctuation(output);
    output = output.replaceFirst(RegExp(r'^(the)\s+', caseSensitive: false), '');
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
