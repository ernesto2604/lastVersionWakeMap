import 'package:flutter/material.dart';
import '../screens/shared/create_alarm_screen.dart';
import '../screens/shared/alarm_trigger_screen.dart';
import '../screens/shared/settings_screen.dart';

class AppRoutes {
  static const String createAlarm = '/create-alarm';
  static const String alarmTrigger = '/alarm-trigger';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        createAlarm: (context) => const CreateAlarmScreen(),
        alarmTrigger: (context) => const AlarmTriggerScreen(),
        settings: (context) => const SettingsScreen(),
      };
}
