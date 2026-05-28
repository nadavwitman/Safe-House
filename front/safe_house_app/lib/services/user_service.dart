import 'api_client.dart';
import 'auth_state.dart';
import 'notification_service.dart';

class UserService {
  static Future<AppUser> getProfile() async {
    final data = await ApiClient.get('/api/user/me');
    AuthState.instance.setUser(data);
    await NotificationService.registerToken();
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
