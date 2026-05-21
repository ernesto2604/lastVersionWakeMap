import 'package:flutter_test/flutter_test.dart';
import 'package:wake_map/services/voice_alarm_service.dart';

void main() {
  group('VoiceAlarmService parseAlarmDraft', () {
    final service = VoiceAlarmService();

    test('parses UK English alarm command with radius', () {
      final draft = service.parseAlarmDraft(
        'Set an alarm called Work for York Station with a radius of 250 metres',
      );

      expect(draft.alarmName, 'Work');
      expect(draft.location, 'York Station');
      expect(draft.radiusMeters, 250);
    });

    test('parses UK English arrival phrase', () {
      final draft = service.parseAlarmDraft(
        'Wake me when I arrive at the British Museum within 400 metres',
      );

      expect(draft.alarmName, 'British Museum');
      expect(draft.location, 'British Museum');
      expect(draft.radiusMeters, 400);
    });

    test('parses Spain Spanish alarm command with radius', () {
      final draft = service.parseAlarmDraft(
        'Crea una alarma llamada Trabajo para la oficina con radio de 300 metros',
      );

      expect(draft.alarmName, 'Trabajo');
      expect(draft.location, 'la oficina');
      expect(draft.radiusMeters, 300);
    });

    test('parses Spain Spanish arrival phrase', () {
      final draft = service.parseAlarmDraft(
        'Avísame cuando llegue a casa dentro de 200 metros',
      );

      expect(draft.alarmName, 'Casa');
      expect(draft.location, 'casa');
      expect(draft.radiusMeters, 200);
    });

    test('clamps spoken radius to supported alarm range', () {
      final low = service.parseAlarmDraft('Set alarm for home at 20 metres');
      final high = service.parseAlarmDraft('Set alarm for home at 2000 metres');

      expect(low.radiusMeters, 100);
      expect(high.radiusMeters, 1000);
    });
  });
}
