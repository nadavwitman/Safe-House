import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local copy of the weekly report, one entry per house.
///
/// The report is regenerated once a week by the server's Sunday job, so the
/// Summary tab would otherwise re-download an unchanged document every time it
/// is opened. Instead the app keeps the last copy here and compares its
/// `generated_at` against the `weekly_report_at` that rides along on the
/// dashboard's existing status poll — a full fetch happens only when those
/// differ, which is roughly once a week per house.
///
/// Entries are a few KB of JSON each and are dropped on sign-out.
class WeeklyReportCache {
  static const _prefix = 'weekly_report_';

  static String _key(String houseId) => '$_prefix$houseId';

  /// Returns the cached report for a house, or null if there is none or the
  /// stored value can no longer be parsed (a shape change across app versions).
  static Future<Map<String, dynamic>?> read(String houseId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(houseId));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      // Unreadable entry is worse than none — drop it so the next sync refills.
      await prefs.remove(_key(houseId));
      return null;
    }
  }

  static Future<void> write(String houseId, Map<String, dynamic> report) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(houseId), jsonEncode(report));
  }

  static Future<void> clear(String houseId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(houseId));
  }

  /// Drops every house's cached report. Called on sign-out so a shared device
  /// doesn't hand the next account a previous resident's wellness data.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
