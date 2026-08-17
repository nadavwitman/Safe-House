import 'api_client.dart';

class HouseService {
  /// Live dashboard poll. Costs one Firestore read server-side — safe to call
  /// on a timer. Returns the vacation flag, the per-sensor last-activity map,
  /// the current AI status with its timestamp, and the weekly report's
  /// generated_at, which the Summary tab uses as a cache key.
  static Future<Map<String, dynamic>> getStatus(String houseId) =>
      ApiClient.get('/api/house/$houseId/status');
}
