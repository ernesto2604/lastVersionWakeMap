import 'package:uuid/uuid.dart';
import '../models/alarm_model.dart';
import 'storage_service.dart';
import 'location_service.dart';

class AlarmService {
  final StorageService _storage;
  final LocationService _location;
  static const _uuid = Uuid();

  AlarmService(this._storage, this._location);

  List<AlarmModel> loadAlarms() => _storage.loadAlarms();

  Future<AlarmModel> createAlarm({
    required String name,
    required String locationLabel,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final alarm = AlarmModel(
      id: _uuid.v4(),
      name: name,
      locationLabel: locationLabel,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      createdAt: DateTime.now(),
    );
    final alarms = _storage.loadAlarms()..add(alarm);
    await _storage.saveAlarms(alarms);
    return alarm;
  }

  Future<void> updateAlarm(AlarmModel updated) async {
    final alarms = _storage.loadAlarms();
    final idx = alarms.indexWhere((a) => a.id == updated.id);
    if (idx != -1) {
      alarms[idx] = updated;
      await _storage.saveAlarms(alarms);
    }
  }

  Future<void> deleteAlarm(String id) async {
    final alarms = _storage.loadAlarms();
    alarms.removeWhere((a) => a.id == id);
    await _storage.saveAlarms(alarms);
  }

  Future<void> toggleAlarm(String id) async {
    final alarms = _storage.loadAlarms();
    final idx = alarms.indexWhere((a) => a.id == id);
    if (idx != -1) {
      alarms[idx].isActive = !alarms[idx].isActive;
      // Reset trigger state when re-activated
      if (alarms[idx].isActive) {
        alarms[idx].hasTriggered = false;
      }
      await _storage.saveAlarms(alarms);
    }
  }

  /// Check all active alarms against the current position.
  /// Returns the first alarm that is within range and hasn't been triggered yet.
  AlarmModel? checkAlarms(
    double currentLat,
    double currentLng,
    List<AlarmModel> alarms,
  ) {
    for (final alarm in alarms) {
      if (!alarm.isActive || alarm.hasTriggered) continue;

      final distance = _location.distanceBetween(
        currentLat,
        currentLng,
        alarm.latitude,
        alarm.longitude,
      );

      if (distance <= alarm.radiusMeters) {
        return alarm;
      }
    }
    return null;
  }

  /// Mark an alarm as triggered so it won't fire again.
  Future<void> markTriggered(String id) async {
    final alarms = _storage.loadAlarms();
    final idx = alarms.indexWhere((a) => a.id == id);
    if (idx != -1) {
      alarms[idx].hasTriggered = true;
      alarms[idx].isActive = false;
      await _storage.saveAlarms(alarms);
    }
  }
}
