import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/alarms/alarm_card.dart';
import '../../widgets/common/empty_state_widget.dart';
import '../../widgets/map/map_wrapper.dart';
import '../shared/alarm_detail_screen.dart';
import '../shared/create_alarm_screen.dart';

class TravellerAlarmsScreen extends StatefulWidget {
  const TravellerAlarmsScreen({super.key});

  @override
  State<TravellerAlarmsScreen> createState() => _TravellerAlarmsScreenState();
}

class _TravellerAlarmsScreenState extends State<TravellerAlarmsScreen> {
  bool _isEditing = false;

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
                          return Row(
                            children: [
                              if (_isEditing)
                                Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(28, 28),
                                    onPressed: () => _confirmDelete(
                                      context,
                                      appState,
                                      alarm.id,
                                      alarm.name,
                                    ),
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.destructiveRed,
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Icon(
                                          CupertinoIcons.minus,
                                          size: 14,
                                          color: CupertinoColors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: AlarmCard(
                                  alarm: alarm,
                                  margin: EdgeInsets.fromLTRB(
                                    _isEditing ? 8 : 16,
                                    6,
                                    16,
                                    6,
                                  ),
                                  onTap: () async {
                                    await showAlarmDetailBottomSheet(
                                      context,
                                      alarm,
                                    );
                                    if (mounted && _isEditing) {
                                      setState(() => _isEditing = false);
                                    }
                                  },
                                  onToggle: () => appState.toggleAlarm(alarm.id),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              Positioned(
                top: topControlsOffset,
                left: 12,
                child: MapWrapper.overlay(
                  GestureDetector(
                    onTap: () => setState(() => _isEditing = !_isEditing),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          height: 48,
                          constraints: const BoxConstraints(minWidth: 86),
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: CupertinoColors.white.withValues(alpha: 0.16),
                            border: Border.all(
                              color: CupertinoColors.white.withValues(alpha: 0.42),
                              width: 0.8,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            _isEditing ? 'Done' : 'Edit',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.86),
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
