import 'api_client.dart';

class InsightsService {
  static Future<Map<String, dynamic>> getWeeklyReport(String houseId) async {
    return ApiClient.get('/api/insights/weekly/$houseId');
  }

  static Future<Map<String, dynamic>> triggerWeeklyReport(
      String houseId) async {
    return ApiClient.post('/api/insights/weekly', {'house_id': houseId});
  }
}
