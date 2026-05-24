import 'api_client.dart';
import 'auth_state.dart';

class AuthService {
  static Future<void> signIn(String email, String password) async {
    final data = await ApiClient.postPublic('/api/auth/signin', {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    await AuthState.instance.setTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    // Signin response has house_ids (not full objects); getProfile() fills houses
    AuthState.instance.currentUser = AppUser(
      userId: data['user_id'] as String? ?? '',
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'user',
      houses: const [],
    );
  }

  static Future<void> signUp(
      String username, String email, String password) async {
    final data = await ApiClient.postPublic('/api/auth/signup', {
      'username': username.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    await AuthState.instance.setTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    AuthState.instance.currentUser = AppUser(
      userId: data['user_id'] as String? ?? '',
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'user',
      houses: const [],
    );
  }

  static Future<void> signOut() async {
    try {
      await ApiClient.post('/api/auth/signout');
    } catch (_) {}
    await AuthState.instance.clear();
  }

  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await ApiClient.post('/api/auth/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  static Future<String> changeUsername(String newUsername) async {
    final data = await ApiClient.post('/api/auth/change-username', {
      'new_username': newUsername.trim(),
    });
    final username = data['username'] as String;
    final user = AuthState.instance.currentUser;
    if (user != null) {
      AuthState.instance.currentUser = AppUser(
        userId: user.userId,
        username: username,
        email: user.email,
        role: user.role,
        houses: user.houses,
      );
    }
    return username;
  }
}
