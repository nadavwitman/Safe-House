import 'api_client.dart';

class InsightsService {
  static Future<Map<String, dynamic>> getWeeklyReport(String houseId) async {
    return ApiClient.get('/api/insights/weekly/$houseId');
  }

  // The app has no way to make a report exist, and that is deliberate. Reports
  // are written by the server's weekly job and by the catch-up that job's
  // failures trigger; the customer app only ever reads them. Nothing a user taps
  // can spend a Gemini call or move the EMA baseline the deltas measure against.

  /// The last 7 days of alerts, newest first. The window is the server's and is not
  /// adjustable. Each entry carries an `id` — the Firestore document id — which is
  /// what acknowledgement is keyed on; see `AlertAckStore`.
  static Future<List<Map<String, dynamic>>> getAlerts(
    String houseId, {
    int? limit,
    bool excludeNormal = false,
  }) async {
    final params = <String>[
      if (limit != null) 'limit=$limit',
      if (excludeNormal) 'exclude_normal=true',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await ApiClient.get('/api/insights/alerts/$houseId$query');
    return (data['alerts'] as List)
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  }
}
