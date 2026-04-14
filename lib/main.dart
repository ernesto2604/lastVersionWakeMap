import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'providers/app_state_provider.dart';
import 'services/storage_service.dart';
import 'services/location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();
  await storageService.init();

  final locationService = LocationService();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppStateProvider(storageService, locationService),
      child: const WakeMapApp(),
    ),
  );
}
