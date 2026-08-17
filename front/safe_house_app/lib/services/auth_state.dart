import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alert_ack_store.dart';
import 'weekly_report_cache.dart';

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

  /// Whether the active house is currently paused for a trip.
  ///
  /// A notifier rather than a plain field because it changes from three places
  /// no single screen owns — the dashboard's status poll, a house switch, and
  /// the server's own scheduler starting a trip at its appointed time. The tabs
  /// live in an IndexedStack and are kept alive, so a screen that read this once
  /// at build never rebuilt to notice any of them, and the Profile toggle sat
  /// showing Off through a vacation the dashboard was already reporting.
  final ValueNotifier<bool> vacationMode = ValueNotifier<bool>(false);

  /// When the active house's stored weekly report was generated, as reported by
  /// the dashboard's status poll. Nothing renders it — the Summary tab compares
  /// it against its cached copy to decide whether to re-download. Published here
  /// rather than passed between screens because the poll that supplies it and the
  /// screen that consumes it are different tabs. Null until the first poll lands.
  final ValueNotifier<String?> weeklyReportAt = ValueNotifier<String?>(null);

  /// How many alerts in the active house's 7-day window this device has not
  /// acknowledged. Published by the Alerts tab and drawn by the shell as the badge
  /// on its nav icon — the count is computed where the alerts already are, and the
  /// only other place that needs it is a widget the Alerts tab does not own.
  final ValueNotifier<int> unreadAlerts = ValueNotifier<int>(0);

  /// The ai_decisions id of the alert currently in effect, from the dashboard poll.
  /// The Alerts tab needs it only to protect its acknowledgement from being pruned:
  /// a long-running alert is still on the banner after it has aged out of the 7-day
  /// list. Null when the house is Normal.
  final ValueNotifier<String?> currentAlertId = ValueNotifier<String?>(null);

  /// Vacation mode is a property of a house, not of the app, so it is cached
  /// per house. A single shared key meant switching houses carried the previous
  /// resident's pause across with it.
  static const _vacationPrefix = 'vacation_mode_';
  static String _vacationKey(String houseId) => '$_vacationPrefix$houseId';

  String? get activeHouseId =>
      _activeHouseId ?? currentUser?.houses.firstOrNull?['house_id'] as String?;

  bool get isLoggedIn => accessToken != null && currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;

  Map<String, dynamic>? _houseById(String? houseId) {
    if (houseId == null) return null;
    return (currentUser?.houses ?? []).cast<Map<String, dynamic>?>().firstWhere(
          (h) => h?['house_id'] == houseId,
          orElse: () => null,
        );
  }

  Map<String, dynamic>? get vacationSchedule =>
      _houseById(activeHouseId)?['vacation_schedule'] as Map<String, dynamic>?;

  /// Rewrites one field on the active house's cached record, so that switching
  /// away and back shows what the server last confirmed rather than the value
  /// this house happened to have at login.
  void _patchActiveHouse(String key, Object? value, {bool remove = false}) {
    final activeId = activeHouseId;
    if (activeId == null || currentUser == null) return;
    final updated = currentUser!.houses.map((h) {
      if (h['house_id'] != activeId) return h;
      final copy = Map<String, dynamic>.from(h);
      if (remove) {
        copy.remove(key);
      } else {
        copy[key] = value;
      }
      return copy;
    }).toList();
    currentUser = AppUser(
      userId: currentUser!.userId,
      username: currentUser!.username,
      email: currentUser!.email,
      role: currentUser!.role,
      houses: updated,
    );
  }

  void updateActiveHouseSchedule(Map<String, dynamic>? schedule) =>
      _patchActiveHouse('vacation_schedule', schedule, remove: schedule == null);

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    _activeHouseId = prefs.getString('active_house_id');
    final activeId = _activeHouseId;
    // Only a cold-start placeholder so the first frame isn't wrong-by-default;
    // the dashboard's first poll replaces it with the server's answer.
    vacationMode.value =
        activeId == null ? false : prefs.getBool(_vacationKey(activeId)) ?? false;
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
    // Adopt the new house's pause state in the same frame as the switch. The
    // dashboard's next poll settles it authoritatively, but that is up to 30s
    // away, and until this was here the toggle simply kept displaying the house
    // the user had just navigated away from.
    vacationMode.value = _houseById(houseId)?['is_vacation'] as bool? ??
        prefs.getBool(_vacationKey(houseId)) ??
        false;
  }

  Future<void> setVacationMode(bool on) async {
    vacationMode.value = on;
    final houseId = activeHouseId;
    if (houseId == null) return;
    _patchActiveHouse('is_vacation', on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vacationKey(houseId), on);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    currentUser = null;
    _activeHouseId = null;
    vacationMode.value = false;
    weeklyReportAt.value = null;
    unreadAlerts.value = 0;
    currentAlertId.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('active_house_id');
    // Every house this device cached a pause for, plus the single shared key
    // used before it was keyed per house.
    await prefs.remove('vacation_mode');
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(_vacationPrefix)).toList()) {
      await prefs.remove(key);
    }
    await WeeklyReportCache.clearAll();
    await AlertAckStore.clearAll();
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
      if (vacationMode.value != serverVacation) {
        vacationMode.value = serverVacation;
        SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool(_vacationKey(activeId), serverVacation));
      }
    }
  }
}
