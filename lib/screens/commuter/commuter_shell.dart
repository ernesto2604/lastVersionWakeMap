import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/navigation/premium_bottom_nav_bar.dart';
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
          extendBody: true,
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
          bottomNavigationBar: PremiumBottomNavBar(
            currentIndex: tabIndex,
            onTap: (i) => _appState.setCommuterTab(i),
            onExtraButtonTap: tabIndex == 1
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Voice input coming soon!')),
                    );
                  }
                : null,
            extraButtonIcon: CupertinoIcons.mic,
            extraButtonLabel: 'Voice',
            items: const [
              PremiumBottomNavItem(
                icon: CupertinoIcons.alarm,
                label: 'Alarms',
              ),
              PremiumBottomNavItem(
                icon: CupertinoIcons.map,
                label: 'Map',
              ),
            ],
          ),
        );
      },
    );
  }
}
