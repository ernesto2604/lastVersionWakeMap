import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../app/routes.dart';
import 'traveller_map_screen.dart';
import 'traveller_guide_screen.dart';
import 'traveller_alarms_screen.dart';

/// Traveller shell with lazy IndexedStack:
/// - Tabs created on first visit (or when programmatically selected), kept alive
/// - Selector rebuilds only on tab index changes
class TravellerShell extends StatefulWidget {
  const TravellerShell({super.key});

  @override
  State<TravellerShell> createState() => _TravellerShellState();
}

class _TravellerShellState extends State<TravellerShell> {
  late final AppStateProvider _appState;

  /// Tabs initialized on demand. Guide tab (1) may be initialized
  /// programmatically by dismissAlarmTrigger() setting travellerTabIndex=1.
  final Set<int> _initializedTabs = {0}; // Tab 0 (Map) created immediately

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
    return Selector<AppStateProvider, int>(
      selector: (_, state) => state.travellerTabIndex,
      builder: (context, tabIndex, _) {
        // Initialize this tab (handles both user taps AND programmatic
        // tab switches like dismissAlarmTrigger setting travellerTabIndex=1)
        _initializedTabs.add(tabIndex);

        return Scaffold(
          body: IndexedStack(
            index: tabIndex,
            children: [
              _initializedTabs.contains(0)
                  ? const TravellerMapScreen()
                  : const SizedBox.shrink(),
              _initializedTabs.contains(1)
                  ? const TravellerGuideScreen()
                  : const SizedBox.shrink(),
              _initializedTabs.contains(2)
                  ? const TravellerAlarmsScreen()
                  : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tabIndex,
            onDestinationSelected: (i) => _appState.setTravellerTab(i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'Guide',
              ),
              NavigationDestination(
                icon: Icon(Icons.alarm_outlined),
                selectedIcon: Icon(Icons.alarm),
                label: 'Alarms',
              ),
            ],
          ),
        );
      },
    );
  }
}
