import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Non-secret backend URL used by the client to reach the guide proxy API.
  static String get apiBaseUrl {
    final configured = _definedApiBaseUrl.trim();
    if (configured.isNotEmpty) return configured;

    // Debug fallback to run with plain `flutter run` while backend is local.
    if (!kDebugMode) return '';

    if (kIsWeb) return 'http://localhost:8080';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android emulator maps host loopback to 10.0.2.2.
        return 'http://10.0.2.2:8080';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://localhost:8080';
    }
  }
}
