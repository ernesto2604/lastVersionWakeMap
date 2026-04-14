import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_mode.dart';
import '../../providers/app_state_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppStateProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current mode
          Card(
            child: ListTile(
              leading: Icon(
                appState.mode == AppMode.commuter
                    ? Icons.commute_rounded
                    : Icons.explore_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Current Mode'),
              subtitle: Text(appState.mode?.displayName ?? 'Not set'),
              trailing: FilledButton.tonal(
                onPressed: () => _switchMode(context, appState),
                child: const Text('Switch'),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Placeholder settings
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.notifications_outlined,
                      color: theme.colorScheme.outline),
                  title: const Text('Notifications'),
                  subtitle: const Text('Coming soon'),
                  enabled: false,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.dark_mode_outlined,
                      color: theme.colorScheme.outline),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Coming soon'),
                  enabled: false,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.info_outline,
                      color: theme.colorScheme.outline),
                  title: const Text('About WakeMap'),
                  subtitle: const Text('Version 1.0.0 MVP'),
                  enabled: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _switchMode(BuildContext context, AppStateProvider appState) {
    final newMode = appState.mode == AppMode.commuter
        ? AppMode.traveller
        : AppMode.commuter;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Mode'),
        content: Text(
          'Switch to ${newMode.displayName} mode? The app layout will change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop(); // Close settings
              appState.setMode(newMode);
            },
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }
}
