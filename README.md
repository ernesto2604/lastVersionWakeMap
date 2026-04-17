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

## Secure Gemini Setup (Backend Proxy)

WakeMap no longer calls Gemini directly from Flutter. The app calls a backend proxy,
and only the backend holds `GEMINI_API_KEY`.

### 1) Run the backend

```bash
cd backend
npm install
```

Create `backend/.env` from `backend/.env.example` and set:

- `GEMINI_API_KEY` (required)
- `GEMINI_MODEL` (optional, default `gemini-2.5-flash`)
- `PORT` (optional, default `8080`)
- `CORS_ORIGIN` (optional, default `*`)

Start the backend:

```bash
npm run dev
```

Verify backend status:

```bash
curl http://localhost:8080/health
```

### 2) Run Flutter pointing to the backend

Debug convenience fallback:
- If `API_BASE_URL` is not provided, WakeMap now auto-uses a debug default:
- Android: `http://10.0.2.2:8080`
- Web/Desktop/iOS simulator: `http://localhost:8080`

This means plain `flutter run` works when your backend is running locally.

Web:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

Android emulator:

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Notes:
- `API_BASE_URL` is non-secret and safe in client config.
- If `API_BASE_URL` is missing or backend is unavailable, WakeMap falls back to the existing mock guide behavior.
- For production, set `CORS_ORIGIN` to your exact frontend origin(s) instead of `*`.

## iOS Setup (Maps + Pods)

WakeMap uses Google Maps + Geolocator on iOS.

1. Set your iOS Google Maps key in all build configs:
   - `ios/Flutter/Debug.xcconfig`
   - `ios/Flutter/Profile.xcconfig`
   - `ios/Flutter/Release.xcconfig`

Use:

```bash
GMS_API_KEY=YOUR_REAL_IOS_MAPS_KEY
```

Info.plist reads this value via `$(GMS_API_KEY)`.

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
- Alarm arrival notifications are local notifications and require user permission on first use.
- Debug HTTP backend calls to `localhost` are allowed via ATS exception in `Info.plist`.

## Build IPA (iOS)

1. Make sure signing is configured in Xcode:
   - Open `ios/Runner.xcworkspace`
   - Select Runner target
   - Set Team and a unique Bundle Identifier

2. Build commands:

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ipa --release
```

3. If needed, open Xcode and Archive manually:
   - Product > Archive

## Deploy Backend To Render

This repo includes a Render blueprint at [render.yaml](render.yaml).

### One-time setup

1. Push your latest code to GitHub.
2. In Render: New > Blueprint, select this repository.
3. Confirm service `wakemap-guide-proxy` and deploy.
4. In Render service environment variables, set:
   - `GEMINI_API_KEY` (required)
   - `GEMINI_MODEL` (optional, default already set)
   - `CORS_ORIGIN` (optional, `*` works for mobile app)

### Verify backend

After deploy, check:

```bash
curl https://wakemap-guide-proxy.onrender.com/health
```

You should see `status: "ok"` and `geminiConfigured: true`.

### iOS Builder behavior

For release builds, the Flutter app now defaults to:

- `https://wakemap-guide-proxy.onrender.com`

So Builder iOS build works without passing `API_BASE_URL`.

If your Render service URL is different, update the fallback in:

- [lib/config/app_config.dart](lib/config/app_config.dart)
