import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/alarms/alarm_card.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../../widgets/map/map_wrapper.dart';
import '../shared/alarm_detail_screen.dart';
import '../shared/create_alarm_screen.dart';
import '../shared/settings_screen.dart';

class TravellerAlarmsScreen extends StatelessWidget {
  const TravellerAlarmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final topControlsOffset = MediaQuery.of(context).padding.top + 8;

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: appState.alarms.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.alarm_off_outlined,
                        title: 'No alarms yet',
                        subtitle:
                            'Tap + to set a destination alarm.\nAfter arrival, your guide will activate.',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          top: topControlsOffset + 52,
                          bottom: 88,
                        ),
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
              ),
              Positioned(
                top: topControlsOffset,
                left: 12,
                child: MapWrapper.circularControl(
                  context: context,
                  onPressed: () => showSettingsBottomSheet(context),
                  icon: CupertinoIcons.settings,
                  tooltip: 'Settings',
                ),
              ),
              Positioned(
                top: topControlsOffset,
                right: 12,
                child: MapWrapper.circularControl(
                  context: context,
                  onPressed: () => showCreateAlarmBottomSheet(context),
                  icon: CupertinoIcons.add,
                  tooltip: 'Add alarm',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(
      BuildContext context, AppStateProvider appState, String id, String name) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Alarm'),
        content: Text('Delete "$name"?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
