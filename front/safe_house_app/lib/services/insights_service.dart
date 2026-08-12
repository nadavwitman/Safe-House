import 'api_client.dart';

class InsightsService {
  static Future<Map<String, dynamic>> getWeeklyReport(String houseId) async {
    return ApiClient.get('/api/insights/weekly/$houseId');
  }

  static Future<Map<String, dynamic>> triggerWeeklyReport(
      String houseId) async {
    return ApiClient.post('/api/insights/weekly', {'house_id': houseId});
  }

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
