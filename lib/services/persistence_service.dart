import 'package:shared_preferences/shared_preferences.dart';

class PersistenceService {
  static const _keyArmed = 'is_anti_theft_armed';
  static const _keyVisibleDeviceIds = 'monitored_device_ids';
  static const _keyAllDeviceIds = 'all_monitored_device_ids';

  static Future<void> setArmed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyArmed, value);
  }

  static Future<bool> isArmed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyArmed) ?? false;
  }

  static Future<void> saveVisibleDeviceIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyVisibleDeviceIds, ids);
  }

  static Future<List<String>> getVisibleDeviceIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyVisibleDeviceIds) ?? [];
  }

  static Future<void> saveAllDeviceIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyAllDeviceIds, ids);
  }

  static Future<List<String>> getAllDeviceIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyAllDeviceIds) ?? [];
  }

  static const _keyThresholdDistance = 'threshold_distance_meters';

  static Future<void> setThresholdDistance(double meters) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_keyThresholdDistance, meters);
}

static Future<double> getThresholdDistance() async {
  final prefs = await SharedPreferences.getInstance();
  // Default to 5.0 meters if no preference is saved[cite: 1]
  return prefs.getDouble(_keyThresholdDistance) ?? 5.0; 
}
}