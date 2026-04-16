import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'providers/app_state_provider.dart';
import 'services/local_notification_service.dart';
import 'services/storage_service.dart';
import 'services/location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();
  await storageService.init();
  await LocalNotificationService.instance.initialize();

  final locationService = LocationService();

  assert(() {
    // Keep debug paint overlays off even if inspector toggles are switched on.
    void disableDebugPaintFlags() {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
      debugPaintLayerBordersEnabled = false;
    }

    disableDebugPaintFlags();
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      disableDebugPaintFlags();
    });
    return true;
  }());

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppStateProvider(storageService, locationService),
      child: const WakeMapApp(),
    ),
  );
}
