import 'package:onesignal_flutter/onesignal_flutter.dart';

class NativeNotificationsService {
  static const _appId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '1a411d13-562a-4bff-8181-a14c01f7abee',
  );
  static bool _initialized = false;

  static void initialize() {
    if (_initialized || _appId.isEmpty) return;
    OneSignal.initialize(_appId);
    _initialized = true;
  }

  static void onNotificationOpened(void Function() handler) {
    if (!_initialized) return;
    OneSignal.Notifications.addClickListener((_) => handler());
  }

  static void signIn(String userId) {
    if (_initialized) OneSignal.login(userId);
  }

  static void signOut() {
    if (_initialized) OneSignal.logout();
  }

  static Future<bool> requestPermission() async {
    if (!_initialized) return false;
    return OneSignal.Notifications.requestPermission(false);
  }

  static void optIn() {
    if (_initialized) OneSignal.User.pushSubscription.optIn();
  }

  static void optOut() {
    if (_initialized) OneSignal.User.pushSubscription.optOut();
  }
}
