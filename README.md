# wake_map

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Gemini Setup (Traveller Guide)

WakeMap supports Gemini-powered traveller guide generation with automatic mock fallback.

1. Open [lib/config/app_secrets.dart](lib/config/app_secrets.dart).
2. Set `AppSecrets.geminiApiKey` to your real Gemini API key.
3. Confirm `AppSecrets.geminiModel` is set to `gemini-2.0-flash` (or another valid model).
4. Run normally:

```bash
flutter run
```

Notes:
- [lib/config/app_secrets.dart](lib/config/app_secrets.dart) is gitignored for local secrets.
- [lib/config/app_secrets.example.dart](lib/config/app_secrets.example.dart) is a safe template.
- For temporary overrides, you can still use `--dart-define` values like `GEMINI_API_KEY` and `GEMINI_MODEL`.

## iOS Setup (Maps + Pods)

WakeMap uses Google Maps + Geolocator on iOS.

1. Open `ios/Runner/Info.plist` and set:
   - `GMSApiKey` to your iOS Maps SDK key.
2. Install iOS pods from the project root:

```bash
flutter pub get
cd ios
pod install
```

3. Build/run on iOS:

```bash
flutter run -d ios
```

Notes:
- iOS deployment target is set to 14.0 to match current plugin requirements.
- Location permission is configured for "When In Use" behavior (foreground MVP tracking).
