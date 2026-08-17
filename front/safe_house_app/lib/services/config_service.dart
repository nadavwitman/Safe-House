import 'api_client.dart';

/// Result of a vacation-related config call.
///
/// These endpoints move more state than the one field they are named after: a
/// schedule that covers right now switches vacation on, cancelling a trip
/// switches it off, and turning monitoring back on deletes a trip already under
/// way. The server reports what it actually did — re-deriving it on the device
/// would mean a second copy of the window arithmetic, drifting from the first.
class VacationResult {
  /// Whether the house is paused now that the call has been applied.
  final bool isVacation;

  /// Whether a stored trip was dropped as part of the call.
  final bool scheduleCleared;

  const VacationResult({required this.isVacation, this.scheduleCleared = false});

  factory VacationResult.from(Map<String, dynamic> json, {bool fallback = false}) =>
      VacationResult(
        isVacation: json['is_vacation'] as bool? ?? fallback,
        scheduleCleared: json['schedule_cleared'] as bool? ?? false,
      );
}

class ConfigService {
  static Future<VacationResult> setMode(String houseId, String mode) async {
    final data = await ApiClient.post('/api/config', {
      'house_id': houseId,
      'mode': mode,
    });
    return VacationResult.from(data, fallback: mode == 'Vacation');
  }

  static Future<VacationResult> setSchedule(
      String houseId, Map<String, dynamic> schedule) async {
    final data = await ApiClient.post('/api/config/vacation-schedule', {
      'house_id': houseId,
      'schedule': schedule,
    });
    return VacationResult.from(data);
  }

  static Future<VacationResult> clearSchedule(String houseId) async {
    final data = await ApiClient.delete('/api/config/vacation-schedule', {
      'house_id': houseId,
    });
    return VacationResult.from(data);
  }
}
