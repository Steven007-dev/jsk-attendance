# JSK Attendance

Native Flutter application for Android and iOS. The interface and app logic are implemented in Dart; this project does not embed the original webpage in a WebView.

## Run

```sh
flutter pub get
flutter run
```

The app keeps the existing JSK Supabase snapshot format (`app_data`, row `main_state`, JSON column `content`) and local storage key. The original public client configuration is used by default. Build-time overrides are available with `SUPABASE_URL` and `SUPABASE_ANON_KEY` Dart defines.

```sh
flutter run \
  --dart-define=SUPABASE_URL=your-project-url \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

## Native setup

- Android uses package ID `com.jsk.attendance` and includes the matching Firebase client configuration for OneSignal notifications.
- iOS uses bundle ID `com.jsk.attendance`. Configure the matching APNs credentials in OneSignal and the Apple developer account before testing push notifications on a device.
- Staff attendance uses foreground location and the geofence values stored in the shared snapshot.

## Build

```sh
flutter build apk
flutter build ios
```

iOS builds require macOS and Xcode.
