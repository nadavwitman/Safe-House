import 'api_client.dart';

class AdminService {
  static Future<List<Map<String, dynamic>>> listHouses() async {
    final data = await ApiClient.get('/api/admin/houses');
    return List<Map<String, dynamic>>.from(data['houses'] as List);
  }

  static Future<Map<String, dynamic>> getHouse(String houseId) async {
    return ApiClient.get('/api/admin/house/$houseId');
  }

  static Future<Map<String, dynamic>> createHouse({
    required String residentName,
    String? address,
    String? emergencyContactPhone,
  }) async {
    return ApiClient.post('/api/admin/house/create', {
      'resident_name': residentName.trim(),
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      if (emergencyContactPhone != null &&
          emergencyContactPhone.trim().isNotEmpty)
        'emergency_contact_phone': emergencyContactPhone.trim(),
    });
  }

  static Future<String> regenerateInviteCode(String houseId) async {
    final data =
        await ApiClient.post('/api/admin/house/$houseId/regenerate-invite');
    return data['invite_code'] as String;
  }

  static Future<String> rotateDeviceToken(String houseId) async {
    final data =
        await ApiClient.post('/api/admin/house/$houseId/rotate-device-token');
    return data['device_token'] as String;
  }

  static Future<void> removeUser(String houseId, String userId) async {
    await ApiClient.delete('/api/admin/house/$houseId/user/$userId');
  }

  static Future<void> setSensorMask(
      String houseId, List<int> mask) async {
    await ApiClient.post('/api/house/sensor-mask', {
      'house_id': houseId,
      'sensor_mask': mask,
    });
  }
}
