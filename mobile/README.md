# LORE mobile

Flutter Android client for the LORE document backend.

## Requirements

- Flutter 3.41+ / Dart 3.11+
- A running LORE backend (see the repository root README)

## Run

```powershell
flutter pub get
flutter run --dart-define=LORE_API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator alias for the host machine and is also the
default. For a physical device on the same trusted network, pass your
computer's LAN address instead and start the backend with
`--host 0.0.0.0`. Do not expose the backend publicly.

Cleartext HTTP is allowed only in debug builds. Release builds require HTTPS.

## Privacy

- All document operations go through the LORE backend; the app never contacts
  an AI provider directly.
- Assisted Mode uses the backend's prepare/confirm flow and pauses for explicit
  approval before any excerpt leaves the backend.
- Conversations are session-only and held in memory.
- No document contents or AI model are stored on the phone.
- A local model, when configured, runs on the backend host, not on Android.

## Test

```powershell
dart format .
flutter analyze
flutter test
```

## Build troubleshooting

If Gradle fails while closing Kotlin incremental caches with
`this and base files have different roots` (common when the project and the
pub cache are on different Windows drives), rebuild once with incremental
Kotlin compilation disabled:

```powershell
flutter build apk --debug -Pkotlin.incremental=false
```
