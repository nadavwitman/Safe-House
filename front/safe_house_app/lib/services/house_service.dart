import 'api_client.dart';

class HouseService {
  static Future<Map<String, dynamic>> getRecentEvents(
    String houseId, {
    int limit = 50,
  }) =>
      ApiClient.get('/api/house/$houseId/recent-events?limit=$limit');
}
