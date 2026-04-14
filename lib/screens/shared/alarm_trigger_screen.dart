import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/alarm_model.dart';
import '../../providers/app_state_provider.dart';
import '../../models/app_mode.dart';

class AlarmTriggerScreen extends StatefulWidget {
  const AlarmTriggerScreen({super.key});

  @override
  State<AlarmTriggerScreen> createState() => _AlarmTriggerScreenState();
}

class _AlarmTriggerScreenState extends State<AlarmTriggerScreen> {
  bool _hasDismissed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.read<AppStateProvider>();

    // Read alarm from route arguments (pushed by shell callback).
    // Falls back to provider's triggeredAlarm for robustness.
    final alarm = ModalRoute.of(context)?.settings.arguments as AlarmModel? ??
        appState.triggeredAlarm;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.8),
                theme.colorScheme.primaryContainer,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Location icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      child: const Icon(
                        Icons.location_on,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Headline
                Text(
                  "You've arrived",
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // Alarm name
                if (alarm != null)
                  Text(
                    alarm.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 12),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'WakeMap detected that you are within the destination area.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(flex: 3),

                // Dismiss button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      // Disable after first tap to prevent double-dismiss
                      onPressed: _hasDismissed ? null : () => _dismiss(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        appState.mode == AppMode.traveller
                            ? 'Start Exploring'
                            : 'Dismiss',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismiss(BuildContext context) {
    setState(() => _hasDismissed = true);
    final appState = context.read<AppStateProvider>();
    appState.dismissAlarmTrigger();
    Navigator.of(context).pop();
  }
}
