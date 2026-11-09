# JSK Attendance — notification work

This branch contains the Flutter preview app that produced the Android APK, plus the current Firebase Hosting and Supabase source used by the notification flow.

- Flutter app: repository root (`lib/`, `android/`, `ios/`, `pubspec.yaml`).
- Firebase Hosting webpage: `web-hosting/www/` with its hosting configuration.
- Supabase Edge Functions and migrations: `supabase/`.

## Build the Android APK

```sh
flutter pub get
flutter build apk --release
```

## Important setup

Signing keys and local signing properties are intentionally not included. Configure signing locally using `android/key.properties.example`. Supabase and Firebase server credentials belong in their service secret settings and are not stored in this repository.

The existing `main` branch is unchanged; this branch is the notification development source snapshot.
