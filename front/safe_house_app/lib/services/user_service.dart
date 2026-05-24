import 'api_client.dart';
import 'auth_state.dart';

class UserService {
  static Future<AppUser> getProfile() async {
    final data = await ApiClient.get('/api/user/me');
    AuthState.instance.setUser(data);
    return AuthState.instance.currentUser!;
  }

  static Future<Map<String, dynamic>> joinHouse(String inviteCode) async {
    final data = await ApiClient.post('/api/user/house/join', {
      'invite_code': inviteCode.trim().toUpperCase(),
    });
    await getProfile();
    return data;
  }
}
