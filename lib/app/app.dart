import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../screens/shared/mode_selection_screen.dart';
import '../screens/commuter/commuter_shell.dart';
import '../screens/traveller/traveller_shell.dart';
import '../models/app_mode.dart';
import 'routes.dart';
import 'theme.dart';

class WakeMapApp extends StatelessWidget {
  const WakeMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Enforce debug paint overlays off (including baseline lines).
    debugPaintBaselinesEnabled = false;
    debugPaintSizeEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintLayerBordersEnabled = false;

    return MaterialApp(
      title: 'WakeMap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routes: AppRoutes.routes,
      home: Consumer<AppStateProvider>(
        builder: (context, state, _) {
          if (state.mode == null) {
            return const ModeSelectionScreen();
          }
          if (state.mode == AppMode.commuter) {
            return const CommuterShell();
          }
          return const TravellerShell();
        },
      ),
    );
  }
}
