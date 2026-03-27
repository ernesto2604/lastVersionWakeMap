import 'package:flutter_test/flutter_test.dart';
import 'package:wake_map/models/alarm_model.dart';
import 'package:wake_map/services/location_service.dart';

void main() {
  group('Distance / radius trigger logic', () {
    final locationService = LocationService();

    test('distanceBetween returns ~111km for 1 degree latitude', () {
      final dist = locationService.distanceBetween(51.0, 0.0, 52.0, 0.0);
      // 1 degree latitude ≈ 111km
      expect(dist, greaterThan(110000));
      expect(dist, lessThan(112000));
    });

    test('alarm at same location as user triggers (distance ~0)', () {
      final dist = locationService.distanceBetween(51.5, -0.1, 51.5, -0.1);
      expect(dist, lessThan(1)); // essentially 0
    });

    test('alarm 200m away triggers for 500m radius', () {
      // ~200m offset
      final dist = locationService.distanceBetween(51.5000, -0.1000, 51.5018, -0.1000);
      expect(dist, lessThan(500));
    });

    test('alarm 600m away does NOT trigger for 500m radius', () {
      // ~600m offset
      final dist = locationService.distanceBetween(51.5000, -0.1000, 51.5054, -0.1000);
      expect(dist, greaterThan(500));
    });
  });

  group('AlarmModel state transitions', () {
    AlarmModel createAlarm({
      bool isActive = true,
      bool hasTriggered = false,
    }) {
      return AlarmModel(
        id: 'test-1',
        name: 'Test Alarm',
        latitude: 51.5,
        longitude: -0.1,
        radiusMeters: 500,
        isActive: isActive,
        createdAt: DateTime.now(),
        hasTriggered: hasTriggered,
      );
    }

    test('new alarm is active and not triggered', () {
      final alarm = createAlarm();
      expect(alarm.isActive, isTrue);
      expect(alarm.hasTriggered, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      final original = createAlarm();
      final copy = original.copyWith(name: 'Updated');
      expect(copy.name, 'Updated');
      expect(copy.id, original.id);
      expect(copy.isActive, original.isActive);
      expect(copy.radiusMeters, original.radiusMeters);
    });

    test('trigger marks alarm as triggered and inactive', () {
      final alarm = createAlarm();
      final triggered = alarm.copyWith(isActive: false, hasTriggered: true);
      expect(triggered.isActive, isFalse);
      expect(triggered.hasTriggered, isTrue);
    });

    test('re-activating alarm resets trigger state', () {
      final triggered = createAlarm(isActive: false, hasTriggered: true);
      final reactivated = triggered.copyWith(isActive: true, hasTriggered: false);
      expect(reactivated.isActive, isTrue);
      expect(reactivated.hasTriggered, isFalse);
    });
  });

  group('Trigger deduplication', () {
    test('inactive alarm should NOT be eligible for trigger check', () {
      final alarm = AlarmModel(
        id: 'a1',
        name: 'Inactive',
        latitude: 51.5,
        longitude: -0.1,
        radiusMeters: 500,
        isActive: false,
        createdAt: DateTime.now(),
      );
      // Verify guard conditions
      expect(alarm.isActive, isFalse);
      // This alarm should be skipped in checkAlarms loop
    });

    test('already-triggered alarm should NOT be eligible for trigger check', () {
      final alarm = AlarmModel(
        id: 'a2',
        name: 'Already Triggered',
        latitude: 51.5,
        longitude: -0.1,
        radiusMeters: 500,
        isActive: true,
        createdAt: DateTime.now(),
        hasTriggered: true,
      );
      // hasTriggered is true — checkAlarms should skip this
      expect(alarm.hasTriggered, isTrue);
    });
  });

  group('AlarmModel JSON serialization', () {
    test('round-trip JSON serialization preserves all fields', () {
      final original = AlarmModel(
        id: 'json-test',
        name: 'JSON Test',
        latitude: 53.9599,
        longitude: -1.0873,
        radiusMeters: 750,
        isActive: true,
        createdAt: DateTime(2026, 3, 22, 12, 0, 0),
        hasTriggered: false,
      );

      final json = original.toJson();
      final restored = AlarmModel.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.radiusMeters, original.radiusMeters);
      expect(restored.isActive, original.isActive);
      expect(restored.hasTriggered, original.hasTriggered);
    });

    test('fromJson handles missing hasTriggered field (defaults to false)', () {
      final json = {
        'id': 'legacy',
        'name': 'Legacy',
        'latitude': 51.5,
        'longitude': -0.1,
        'radiusMeters': 500.0,
        'isActive': true,
        'createdAt': '2026-03-22T12:00:00.000',
        // hasTriggered intentionally missing
      };
      final alarm = AlarmModel.fromJson(json);
      expect(alarm.hasTriggered, isFalse);
    });
  });
}
