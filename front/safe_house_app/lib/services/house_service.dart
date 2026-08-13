import 'api_client.dart';

class HouseService {
  /// Live dashboard poll. Costs one Firestore read server-side — safe to call
  /// on a timer. Returns {is_vacation, last_activity}.
  static Future<Map<String, dynamic>> getStatus(String houseId) =>
      ApiClient.get('/api/house/$houseId/status');

  /// Full sensor-reading history. Costs `limit` Firestore reads — for on-demand
  /// views only, never poll this.
  static Future<Map<String, dynamic>> getRecentEvents(
    String houseId, {
    int limit = 50,
  }) =>
      ApiClient.get('/api/house/$houseId/recent-events?limit=$limit');
}
