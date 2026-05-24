import 'api_client.dart';

class ConfigService {
  static Future<void> setMode(String houseId, String mode) async {
    await ApiClient.post('/api/config', {
      'house_id': houseId,
      'mode': mode,
    });
  }

  static Future<void> setSchedule(
      String houseId, Map<String, dynamic> schedule) async {
    await ApiClient.post('/api/config/vacation-schedule', {
      'house_id': houseId,
      'schedule': schedule,
    });
  }

  static Future<void> clearSchedule(String houseId) async {
    await ApiClient.delete('/api/config/vacation-schedule', {
      'house_id': houseId,
    });
  }
}
