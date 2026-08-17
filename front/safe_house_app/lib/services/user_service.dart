import 'api_client.dart';
import 'auth_state.dart';
import 'notification_service.dart';

class UserService {
  /// Loads the account and registers this device for push. Use at sign-in and
  /// launch — the two moments where the push registration genuinely needs
  /// refreshing.
  static Future<AppUser> getProfile() async {
    final user = await refresh();
    await NotificationService.registerToken();
    return user;
  }

  /// Re-reads the account without touching push registration, for the routine
  /// freshening the Profile tab does whenever it becomes visible. Re-POSTing an
  /// unchanged FCM token on every visit is a write the server does not need.
  static Future<AppUser> refresh() async {
    final data = await ApiClient.get('/api/user/me');
    AuthState.instance.setUser(data);
    return AuthState.instance.currentUser!;
  }

  static Future<Map<String, dynamic>> joinHouse(String inviteCode) async {
    final data = await ApiClient.post('/api/user/house/join', {
      'invite_code': inviteCode.trim().toUpperCase(),
    });
    // Refresh tokens so the new house_id is embedded in the JWT claims
    // before any @house_member_required endpoint is called.
    await ApiClient.refreshTokens();
    await getProfile();
    return data;
  }
}
