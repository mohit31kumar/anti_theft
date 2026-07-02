import 'dart:math';

class SignalUtils {
  // Environmental constants
  static const double measuredPower = -60.0; // RSSI at 1 meter
  static const double environmentalFactor = 3.0; // Path-loss exponent

  /// Converts RSSI to an estimated distance in meters
  static double rssiToMeters(int rssi) {
    if (rssi == 0) return -1.0;
    return pow(10, (measuredPower - rssi) / (10 * environmentalFactor)).toDouble();
  }

  /// Converts a distance in meters back to the required RSSI threshold[cite: 1]
  static int metersToRssi(double meters) {
    if (meters <= 0) return -60;
    return (measuredPower - (10 * environmentalFactor * (log(meters) / ln10))).round();
  }
}