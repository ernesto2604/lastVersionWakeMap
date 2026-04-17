import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _definedGoogleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  // Fallback key used by current local builds. Restrict this key by package
  // name / bundle id and API scope in Google Cloud Console.
  static const String _fallbackGoogleMapsApiKey =
      'AIzaSyCGo89ToPeDSy-QOzmbpeNqCEncJLTRjjI';

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

  static String get googleMapsApiKey {
    final configured = _definedGoogleMapsApiKey.trim();
    if (configured.isNotEmpty) return configured;
    return _fallbackGoogleMapsApiKey;
  }
}
