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
    final lower = cleanedTranscript.toLowerCase();

    String location = '';
    final patterns = <RegExp>[
      RegExp(r'when\s+i\s+arrive\s+(?:to|at|in)\s+(.+)', caseSensitive: false),
      RegExp(r'when\s+i\s+get\s+to\s+(.+)', caseSensitive: false),
      RegExp(r'when\s+i\s+reach\s+(.+)', caseSensitive: false),
      RegExp(r'(?:arrive|reach|get)\s+(?:to|at|in)\s+(.+)', caseSensitive: false),
      RegExp(r'\bto\s+(.+)', caseSensitive: false),
      RegExp(r'\bat\s+(.+)', caseSensitive: false),
      RegExp(r'\bin\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanedTranscript);
      if (match != null && match.groupCount >= 1) {
        location = (match.group(1) ?? '').trim();
        if (location.isNotEmpty) break;
      }
    }

    if (location.isEmpty) {
      location = cleanedTranscript
          .replaceFirst(RegExp(r'^put\s+an\s+alarm\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^set\s+an\s+alarm\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^create\s+an\s+alarm\s*', caseSensitive: false), '')
          .trim();
    }

    location = _cleanLocation(location);

    String alarmName;
    if (location.isEmpty) {
      alarmName = lower.contains('home') ? 'Home Alarm' : 'Voice Alarm';
      location = cleanedTranscript;
    } else {
      final firstChunk = location.split(',').first.trim();
      alarmName = firstChunk.isEmpty ? 'Voice Alarm' : _toTitleCase(firstChunk);
    }

    return VoiceAlarmDraft(
      alarmName: alarmName,
      location: location,
      radiusMeters: 100,
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
