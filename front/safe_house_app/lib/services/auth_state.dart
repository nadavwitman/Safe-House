import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String userId;
  final String username;
  final String email;
  final String role;
  final List<Map<String, dynamic>> houses;

  const AppUser({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.houses,
  });

  bool get isAdmin => role == 'admin';
}

class AuthState {
  AuthState._();
  static final AuthState instance = AuthState._();

  String? accessToken;
  String? refreshToken;
  AppUser? currentUser;
  String? _activeHouseId;
  bool _vacationMode = false;

  String? get activeHouseId =>
      _activeHouseId ?? currentUser?.houses.firstOrNull?['house_id'] as String?;

  bool get vacationMode => _vacationMode;
  bool get isLoggedIn => accessToken != null && currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;

  Map<String, dynamic>? get vacationSchedule {
    final activeId = activeHouseId;
    if (activeId == null) return null;
    final houses = currentUser?.houses ?? [];
    final house = houses.cast<Map<String, dynamic>?>().firstWhere(
      (h) => h?['house_id'] == activeId,
      orElse: () => null,
    );
    return house?['vacation_schedule'] as Map<String, dynamic>?;
  }

  void updateActiveHouseSchedule(Map<String, dynamic>? schedule) {
    final activeId = activeHouseId;
    if (activeId == null || currentUser == null) return;
    final updated = currentUser!.houses.map((h) {
      if (h['house_id'] == activeId) {
        final copy = Map<String, dynamic>.from(h);
        if (schedule == null) {
          copy.remove('vacation_schedule');
        } else {
          copy['vacation_schedule'] = schedule;
        }
        return copy;
      }
      return h;
    }).toList();
    currentUser = AppUser(
      userId: currentUser!.userId,
      username: currentUser!.username,
      email: currentUser!.email,
      role: currentUser!.role,
      houses: updated,
    );
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    _activeHouseId = prefs.getString('active_house_id');
    _vacationMode = prefs.getBool('vacation_mode') ?? false;
  }

  Future<void> setTokens(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> setActiveHouse(String houseId) async {
    _activeHouseId = houseId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_house_id', houseId);
  }

  Future<void> setVacationMode(bool on) async {
    _vacationMode = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vacation_mode', on);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    currentUser = null;
    _activeHouseId = null;
    _vacationMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('active_house_id');
    await prefs.remove('vacation_mode');
  }

  void setUser(Map<String, dynamic> json) {
    final housesList = (json['houses'] as List?)
            ?.map((h) => Map<String, dynamic>.from(h as Map))
            .toList() ??
        [];
    currentUser = AppUser(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      houses: housesList,
    );
    if (_activeHouseId == null && housesList.isNotEmpty) {
      _activeHouseId = housesList.first['house_id'] as String?;
    }
    // Sync vacation mode from the active house returned by the server
    final activeId = _activeHouseId;
    if (activeId != null && housesList.isNotEmpty) {
      final activeHouse = housesList.firstWhere(
        (h) => h['house_id'] == activeId,
        orElse: () => housesList.first,
      );
      final serverVacation = activeHouse['is_vacation'] as bool? ?? false;
      if (_vacationMode != serverVacation) {
        _vacationMode = serverVacation;
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool('vacation_mode', serverVacation));
      }
    }
  }
}
