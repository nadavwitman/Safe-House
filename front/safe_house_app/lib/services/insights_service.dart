import 'api_client.dart';

class InsightsService {
  static Future<Map<String, dynamic>> getWeeklyReport(String houseId) async {
    return ApiClient.get('/api/insights/weekly/$houseId');
  }

  static Future<Map<String, dynamic>> triggerWeeklyReport(
      String houseId) async {
    return ApiClient.post('/api/insights/weekly', {'house_id': houseId});
  }

  static Future<List<Map<String, dynamic>>> getAlerts(String houseId) async {
    final data = await ApiClient.get('/api/insights/alerts/$houseId');
    return (data['alerts'] as List)
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  }
}
