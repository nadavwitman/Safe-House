import 'package:shared_preferences/shared_preferences.dart';

/// Which alerts this device has acknowledged, per house.
///
/// Acknowledgement is device-local and never reaches the server, the same choice
/// the dashboard banner makes: "I have read this" is a fact about a reader, not
/// about the house, and the AI owns the house's actual status. The cost is that
/// acknowledging on one phone does not clear the badge on another family member's
/// — each person marks their own alerts read, which is how a mailbox behaves.
///
/// Entries are keyed on the Firestore document id the alerts endpoint returns.
/// Nothing else on an alert is unique enough: two sensors can fault in the same
/// second, and a title repeats every time the same anomaly recurs.
class AlertAckStore {
  static const _prefix = 'acked_alerts_';

  static String _key(String houseId) => '$_prefix$houseId';

  /// The acknowledged ids for a house. Unknown houses read as empty.
  static Future<Set<String>> read(String houseId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(houseId)) ?? const <String>[]).toSet();
  }

  /// Marks one alert acknowledged, keeping everything already stored.
  static Future<void> add(String houseId, String alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_key(houseId)) ?? const <String>[]).toSet();
    if (!current.add(alertId)) return;
    await prefs.setStringList(_key(houseId), current.toList());
  }

  /// Drops acknowledgements for alerts the server no longer returns.
  ///
  /// Without this the list only ever grows: the screen shows a 7-day window, so an
  /// id acknowledged last month can never appear again, yet would sit in storage
  /// for the life of the install. [liveIds] is the set from the most recent fetch —
  /// anything outside it has aged out of the window and is safe to forget.
  ///
  /// Callers must only pass a *complete* fetch. Pruning against a partial or failed
  /// response would forget acknowledgements for alerts that are still on screen,
  /// and they would all reappear as unread.
  ///
  /// [keep] protects ids that are still in use but outside the window. The one that
  /// matters is the alert currently in effect: a house that entered Warning three
  /// weeks ago and never recovered still shows it on the dashboard banner, but it
  /// has long since aged out of the 7-day list — without this its acknowledgement
  /// would be pruned and the banner would come back from the dead on next launch.
  static Future<void> prune(
    String houseId,
    Set<String> liveIds, {
    String? keep,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key(houseId));
    if (current == null) return;
    final kept =
        current.where((id) => id == keep || liveIds.contains(id)).toList();
    if (kept.length == current.length) return;
    await prefs.setStringList(_key(houseId), kept);
  }

  /// Clears every house's acknowledgements. Called on logout — the next account to
  /// use this device must not inherit what the previous one had read.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }
}
