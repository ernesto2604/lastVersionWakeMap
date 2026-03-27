import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../app/routes.dart';
import '../../widgets/alarms/alarm_card.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../shared/alarm_detail_screen.dart';

class TravellerAlarmsScreen extends StatelessWidget {
  const TravellerAlarmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('My Alarms'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.settings),
                tooltip: 'Settings',
              ),
            ],
          ),
          body: appState.alarms.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.alarm_off_outlined,
                  title: 'No alarms yet',
                  subtitle:
                      'Tap + to set a destination alarm.\nAfter arrival, your guide will activate.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  itemCount: appState.alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = appState.alarms[index];
                    return AlarmCard(
                      alarm: alarm,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlarmDetailScreen(alarm: alarm),
                        ),
                      ),
                      onToggle: () => appState.toggleAlarm(alarm.id),
                      onDelete: () =>
                          _confirmDelete(context, appState, alarm.id, alarm.name),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.createAlarm),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _confirmDelete(
      BuildContext context, AppStateProvider appState, String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Alarm'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              appState.deleteAlarm(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
