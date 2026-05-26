import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'api_client.dart';
import 'auth_state.dart';

// Must be a top-level function — Flutter's background isolate cannot reach class members.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized by the time this fires.
  // Nothing extra to do: the OS displays the notification from the FCM payload.
}

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // FCM on web requires a service worker + VAPID key that we haven't configured.
    // Skip silently so startup auth flow is never broken by a missing FCM token.
    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    try {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);

      final token = await _fcm.getToken();
      if (token != null && AuthState.instance.isLoggedIn) {
        await _register(token);
      }

      _fcm.onTokenRefresh.listen((newToken) async {
        if (AuthState.instance.isLoggedIn) {
          await _register(newToken);
        }
      });
    } catch (_) {}
  }

  static Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _register(token);
      }
    } catch (_) {}
  }

  static Future<void> unregisterToken() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await ApiClient.delete('/api/user/fcm-token', {'fcm_token': token});
      }
    } catch (_) {}
  }

  static Future<void> _register(String token) async {
    try {
      await ApiClient.post('/api/user/fcm-token', {'fcm_token': token});
    } catch (_) {}
  }
}
