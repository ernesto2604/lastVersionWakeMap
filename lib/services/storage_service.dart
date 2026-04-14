import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_model.dart';
import '../models/app_mode.dart';

class StorageService {
  static const String _modeKey = 'app_mode';
  static const String _alarmsKey = 'alarms';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Mode ──

  AppMode? getSavedMode() {
    final value = _prefs.getString(_modeKey);
    if (value == null) return null;
    return AppMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => AppMode.commuter,
    );
  }

  Future<void> saveMode(AppMode mode) async {
    await _prefs.setString(_modeKey, mode.name);
  }

  // ── Alarms ──

  List<AlarmModel> loadAlarms() {
    final raw = _prefs.getStringList(_alarmsKey);
    if (raw == null) return [];
    return raw.map((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return AlarmModel.fromJson(map);
    }).toList();
  }

  Future<void> saveAlarms(List<AlarmModel> alarms) async {
    final raw = alarms.map((a) => jsonEncode(a.toJson())).toList();
    await _prefs.setStringList(_alarmsKey, raw);
  }
}
