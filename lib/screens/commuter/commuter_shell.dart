import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/navigation/premium_bottom_nav_bar.dart';
import '../../providers/app_state_provider.dart';
import '../../app/routes.dart';
import '../../services/places_service.dart';
import '../../services/voice_alarm_service.dart';
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
  final VoiceAlarmService _voiceAlarmService = VoiceAlarmService();
  final PlacesService _placesService = PlacesService();
  bool _isCapturingVoice = false;
  String _liveTranscript = '';

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

  Future<void> _onVoiceAlarmPressed() async {
    if (_isCapturingVoice) return;

    setState(() {
      _isCapturingVoice = true;
      _liveTranscript = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listening... say your alarm destination.')),
    );

    try {
      final transcript = await _voiceAlarmService.listenOnce(
        onTranscriptChanged: (text) {
          if (!mounted || !_isCapturingVoice) return;
          setState(() => _liveTranscript = text);
        },
      );
      if (!mounted) return;

      if (transcript == null || transcript.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No voice input detected. Try again.')),
        );
        return;
      }

      final draft = _voiceAlarmService.parseAlarmDraft(transcript);

      final sessionToken = DateTime.now().microsecondsSinceEpoch.toString();
      final suggestions = await _placesService.autocomplete(
        query: draft.location,
        sessionToken: sessionToken,
      );

      if (!mounted) return;

      if (suggestions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resolve location: ${draft.location}')),
        );
        return;
      }

      final best = suggestions.first;
      final coordinates = await _placesService.getPlaceCoordinates(
        placeId: best.placeId,
        sessionToken: sessionToken,
      );

      if (!mounted) return;

      if (coordinates == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch map coordinates for ${best.description}')),
        );
        return;
      }

      await _appState.createAlarm(
        name: draft.alarmName,
        locationLabel: best.description,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        radiusMeters: 100,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm created: ${draft.alarmName} (100 m)')),
      );
    } on VoiceCaptureException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice capture failed. Please try again.')),
      );
    } finally {
      if (mounted && _isCapturingVoice) {
        setState(() {
          _isCapturingVoice = false;
          _liveTranscript = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Selector: only rebuild shell when tab index changes
    return Selector<AppStateProvider, int>(
      selector: (_, state) => state.commuterTabIndex,
      builder: (context, tabIndex, _) {
        // Mark this tab as initialized (lazy)
        _initializedTabs.add(tabIndex);

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final navBottomPadding = math.max(10.0, bottomInset * 0.55);
        final transcriptBottomOffset = 62.0 + navBottomPadding + 8;

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              IndexedStack(
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
              if (_isCapturingVoice && _liveTranscript.trim().isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: transcriptBottomOffset,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CupertinoColors.systemRed.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(
                          _liveTranscript,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: PremiumBottomNavBar(
            currentIndex: tabIndex,
            onTap: (i) => _appState.setCommuterTab(i),
            onExtraButtonTap: tabIndex == 1
                ? _onVoiceAlarmPressed
                : null,
            extraButtonIcon: _isCapturingVoice
              ? CupertinoIcons.mic_fill
              : CupertinoIcons.mic,
            extraButtonLabel: _isCapturingVoice ? 'Listening' : 'Voice',
            extraButtonIconColor: _isCapturingVoice
              ? CupertinoColors.systemRed
              : null,
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
