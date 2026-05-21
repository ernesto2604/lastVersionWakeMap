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

  Future<void> normalizeActiveAlarms() async {
    final alarms = _storage.loadAlarms();
    if (_enforceSingleActiveAlarm(alarms)) {
      await _storage.saveAlarms(alarms);
    }
  }

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
    final alarms = _storage.loadAlarms();
    for (final existing in alarms) {
      existing.isActive = false;
    }
    alarms.add(alarm);
    await _storage.saveAlarms(alarms);
    return alarm;
  }

  Future<void> updateAlarm(AlarmModel updated) async {
    final alarms = _storage.loadAlarms();
    final idx = alarms.indexWhere((a) => a.id == updated.id);
    if (idx != -1) {
      if (updated.isActive) {
        updated.hasTriggered = false;
        for (var i = 0; i < alarms.length; i++) {
          if (i != idx) alarms[i].isActive = false;
        }
      }
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
      final shouldActivate = !alarms[idx].isActive;
      if (shouldActivate) {
        for (final alarm in alarms) {
          alarm.isActive = false;
        }
      }
      alarms[idx].isActive = shouldActivate;
      if (shouldActivate) alarms[idx].hasTriggered = false;
      await _storage.saveAlarms(alarms);
    }
  }

  Future<void> deactivateAllAlarms() async {
    final alarms = _storage.loadAlarms();
    var changed = false;
    for (final alarm in alarms) {
      if (alarm.isActive) {
        alarm.isActive = false;
        changed = true;
      }
    }
    if (changed) {
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
      for (var i = 0; i < alarms.length; i++) {
        if (i != idx) alarms[i].isActive = false;
      }
      await _storage.saveAlarms(alarms);
    }
  }

  bool _enforceSingleActiveAlarm(List<AlarmModel> alarms) {
    var changed = false;
    for (final alarm in alarms) {
      if (alarm.isActive && alarm.hasTriggered) {
        alarm.isActive = false;
        changed = true;
      }
    }

    final activeAlarms = alarms.where((a) => a.isActive).toList();
    if (activeAlarms.length <= 1) return changed;

    activeAlarms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final activeIdToKeep = activeAlarms.first.id;
    for (final alarm in alarms) {
      if (alarm.isActive && alarm.id != activeIdToKeep) {
        alarm.isActive = false;
        changed = true;
      }
    }
    return changed;
  }
}
