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
