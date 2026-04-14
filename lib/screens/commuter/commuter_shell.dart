import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../app/routes.dart';
import 'commuter_alarms_screen.dart';
import 'commuter_map_screen.dart';

/// Commuter shell with lazy IndexedStack:
/// - Tabs are created on first visit but kept alive thereafter (no map recreation)
/// - Uses Selector to rebuild ONLY on tab index changes (not every notifyListeners)
class CommuterShell extends StatefulWidget {
  const CommuterShell({super.key});

  @override
  State<CommuterShell> createState() => _CommuterShellState();
}

class _CommuterShellState extends State<CommuterShell> {
  late final AppStateProvider _appState;

  /// Tracks which tabs have been visited. Only visited tabs get their
  /// real widget created; unvisited tabs stay as lightweight placeholders.
  final Set<int> _initializedTabs = {0}; // Tab 0 (Alarms) created immediately

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _appState.registerAlarmTriggerCallback(_onAlarmTriggered);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appState.startLocationTracking();
    });
  }

  @override
  void dispose() {
    _appState.unregisterAlarmTriggerCallback();
    super.dispose();
  }

  void _onAlarmTriggered() {
    if (!mounted) return;
    final alarm = _appState.triggeredAlarm;
    if (alarm == null) return;

    Navigator.of(context)
        .pushNamed(AppRoutes.alarmTrigger, arguments: alarm)
        .then((_) => _appState.acknowledgeTriggerNavigation());
  }

  @override
  Widget build(BuildContext context) {
    // Selector: only rebuild shell when tab index changes
    return Selector<AppStateProvider, int>(
      selector: (_, state) => state.commuterTabIndex,
      builder: (context, tabIndex, _) {
        // Mark this tab as initialized (lazy)
        _initializedTabs.add(tabIndex);

        return Scaffold(
          body: IndexedStack(
            index: tabIndex,
            children: [
              // Tab 0: Alarms — always created (initialized in set)
              _initializedTabs.contains(0)
                  ? const CommuterAlarmsScreen()
                  : const SizedBox.shrink(),
              // Tab 1: Map — created on first visit, kept alive by IndexedStack
              _initializedTabs.contains(1)
                  ? const CommuterMapScreen()
                  : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tabIndex,
            onDestinationSelected: (i) => _appState.setCommuterTab(i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.alarm_outlined),
                selectedIcon: Icon(Icons.alarm),
                label: 'Alarms',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
            ],
          ),
        );
      },
    );
  }
}
