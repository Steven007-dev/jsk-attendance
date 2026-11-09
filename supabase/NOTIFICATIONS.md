# JSK push notifications with Firebase Cloud Messaging

The app continues to save each notification in the JSK inbox in Supabase. The `app_data` database webhook calls `push-outbox`, which sends that inbox item through Firebase Cloud Messaging (FCM) to every registered device for its recipient. The web page and the native Flutter app register their own FCM token through the authenticated `jsk-sync` function. Device tokens and the FCM service credential are private server data; they are not stored in the website bundle.

FCM can display an operating-system notification while Android or a supported browser is backgrounded, locked, or closed. People must sign in, opt in to notifications, and allow the device permission first. Delivery still depends on network access, OS/browser policy, battery settings, and valid tokens; no push service can guarantee that every device displays a message at a precise time.

## Firebase setup (one-time)

1. In Firebase project `jsk-attendance`, keep the Android app `com.jsk.attendance` and its `google-services.json` in `android/app/`.
2. Register a Firebase **Web app** in Project settings. Copy its public web config `appId` to `www/fcm-config.js`.
3. In Firebase Project settings → Cloud Messaging → Web Push certificates, generate or copy the public VAPID key to `JSK_FCM_VAPID_KEY` in `www/fcm-config.js`. This public key belongs in the browser; never put a private service-account key there.
4. Create a dedicated Firebase service account allowed to send Cloud Messaging messages. Store its entire JSON key in a Supabase Edge Function secret. The sender accepts `FCM_SERVICE_ACCOUNT_JSON`; this project already has `FIREBASE_SERVICE_ACCOUNT`, which it can reuse if it contains the `jsk-attendance` service account JSON. Keep it in a password manager or other secure place and never paste it into chat, source code, GitHub, or `www/`.
5. If building a native iOS app, also register its iOS bundle ID in Firebase, add its `GoogleService-Info.plist` to the Runner target, enable Push Notifications and Background Modes in Xcode, and configure an APNs authentication key in Firebase. Without APNs configuration, native iOS pushes cannot arrive. The website can also be installed from Safari’s Share → Add to Home Screen on supported iOS versions; browser push requires that installed web app and notification permission.

## Supabase setup and deployment

Apply migrations in order, including `202611080001_fcm_device_tokens.sql`. The existing `202610310001_push_delivery_receipts.sql` marks old inbox entries as historical, preventing a notification blast when push is enabled.

Set Edge Function secrets in the Supabase Dashboard under Edge Functions → Secrets:

- `FIREBASE_SERVICE_ACCOUNT` (existing) or `FCM_SERVICE_ACCOUNT_JSON`: Firebase service-account JSON for project `jsk-attendance`.
- `PUSH_WEBHOOK_SECRET`: the same random secret (at least 32 characters) already used by the `app_data` webhook.

Supabase provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Never expose the service-role key in the app or website.

Deploy `jsk-sync` and `push-outbox`. Configure `push-outbox` with JWT verification disabled because it is called by the database webhook; it authenticates each webhook request using `x-push-webhook-secret`. In Supabase Database Webhooks, enable INSERT and UPDATE on `public.app_data`, target the `push-outbox` function, and set that header to the same `PUSH_WEBHOOK_SECRET`.

Deploy Firebase Hosting after filling in `www/fcm-config.js`. The website registers `/sw.js` at the root scope. HTTPS is required for web push.

## User and device steps

Each real account signs in on that device, enables Phone notifications in Settings, and allows the browser or operating-system prompt. The user must open the app/site once after installing or reinstalling so its device token can be registered. Signing out removes that device’s account association. If they turn alerts off or revoke permission, that device will stop receiving pushes. Android displays notification payloads when the app is backgrounded or closed; foreground notifications are shown by the Flutter local-notification handler. The website uses FCM’s service-worker notification display and opens the JSK Notifications page when tapped.

The server records delivery receipts per notification and device, so one device’s success does not prevent another device from retrying. Invalid FCM tokens are removed. The function uses bounded parallel sends; for sustained 10,000+ audience broadcasts, use a durable queue and chunked workers with monitoring rather than assuming one database-webhook invocation can never time out.

## Build the Android app

From the Flutter project root, run `flutter pub get` then `flutter build apk --release`. The Android app needs a new APK installed by users to receive the native FCM integration. Keep the production signing key and versioning process consistent with the previously distributed APK.
