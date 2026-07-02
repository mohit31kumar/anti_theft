import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'persistence_service.dart';
import '../utils/signal_utils.dart';

enum DeviceState { safe, warning, alert }

class DeviceProximityState {
  String deviceId;
  String deviceName;
  int smoothedRssi;
  List<int> rssiBuffer;
  DeviceState state;
  int stateChangedAt;
  int consecutiveLowReadings;

  DeviceProximityState({
    required this.deviceId,
    required this.deviceName,
    required this.smoothedRssi,
    required this.rssiBuffer,
    required this.state,
    required this.stateChangedAt,
    required this.consecutiveLowReadings,
  });

  DeviceProximityState copyWith({
    int? smoothedRssi,
    List<int>? rssiBuffer,
    DeviceState? state,
    int? stateChangedAt,
    int? consecutiveLowReadings,
  }) {
    return DeviceProximityState(
      deviceId: deviceId,
      deviceName: deviceName,
      smoothedRssi: smoothedRssi ?? this.smoothedRssi,
      rssiBuffer: List<int>.from(rssiBuffer ?? this.rssiBuffer),
      state: state ?? this.state,
      stateChangedAt: stateChangedAt ?? this.stateChangedAt,
      consecutiveLowReadings: consecutiveLowReadings ?? this.consecutiveLowReadings,
    );
  }
}

class BleTaskHandler extends TaskHandler {
  List<String> _monitoredIds = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  SendPort? _mainSendPort;
  ReceivePort? _receivePort; // Used for bulletproof UI communication
  final Map<String, DeviceProximityState> _deviceStates = {};

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAlarmRinging = false;
  double _thresholdMeters = 5.0;
  int _dynamicRssiFar = -75;

  static const int rssiBufferSize = 5;
  static const int alertCount = 3;
  static const int alertHoldMs = 2000;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _mainSendPort = sendPort;
    
    // Setup manual port to receive slider updates from UI
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping('anti_theft_service_port');
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, 'anti_theft_service_port');
    _receivePort!.listen(_handleIncomingData);

    _thresholdMeters = await PersistenceService.getThresholdDistance();
    _dynamicRssiFar = SignalUtils.metersToRssi(_thresholdMeters);
    _monitoredIds = await PersistenceService.getAllDeviceIds();

    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _startBackgroundScan();
  }

  void _startBackgroundScan() async {
    await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first;
    await FlutterBluePlus.startScan(timeout: null, androidUsesFineLocation: true);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (_monitoredIds.contains(r.device.id.id)) {
          _processRssiUpdate({
            'device_id': r.device.id.id,
            'rssi': r.rssi,
            'device_name': r.device.platformName,
          });
        }
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    final hasAlert = _deviceStates.values.any((d) => d.state == DeviceState.alert);

    if (hasAlert) {
      if (!_isAlarmRinging) _startContinuousAlarm();
    } else {
      if (_isAlarmRinging) _stopContinuousAlarm();
    }
  }

  void _startContinuousAlarm() async {
    _isAlarmRinging = true;
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
    
    // ✅ WARNING FIXED: Removed '?? false'
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
    }

    FlutterForegroundTask.updateService(
      notificationTitle: '🚨 SECURITY ALERT 🚨',
      notificationText: 'A device has been lost or moved!',
    );
    _mainSendPort?.send({'event': 'ALARM_TRIGGERED'});
  }

  void _stopContinuousAlarm() {
    _isAlarmRinging = false;
    _audioPlayer.stop();
    Vibration.cancel();
    
    FlutterForegroundTask.updateService(
      notificationTitle: 'Anti-Theft Active',
      notificationText: 'All devices safe.',
    );
  }

  // ✅ WARNING FIXED: Removed @override and renamed to avoid conflicts
  void _handleIncomingData(dynamic data) {
    if (data is! Map) return;
    final action = data['action'] ?? '';
    
    if (action == 'update_threshold') {
      _thresholdMeters = data['value'] ?? 5.0;
      _dynamicRssiFar = SignalUtils.metersToRssi(_thresholdMeters);
      print("Dynamic Threshold Updated in Background: $_thresholdMeters meters");
    } else if (action == 'remove_device') {
      final deviceId = data['device_id'] ?? '';
      _monitoredIds.remove(deviceId);
      _deviceStates.remove(deviceId);
      print("Device $deviceId removed from background monitoring");
      final aliveIds = _monitoredIds.length;
      FlutterForegroundTask.updateService(
        notificationTitle: 'Anti-Theft Active',
        notificationText: 'Monitoring $aliveIds devices',
      );
    } else if (action == 'add_device') {
      final deviceId = data['device_id'] ?? '';
      final deviceName = data['device_name'] ?? 'Unknown';
      if (!_monitoredIds.contains(deviceId)) {
        _monitoredIds.add(deviceId);
        // Pre-seed a proximity state so monitoring starts immediately
        _processRssiUpdate({
          'device_id': deviceId,
          'rssi': -60,
          'device_name': deviceName,
        });
        print("Device $deviceId added to background monitoring");
      }
      final aliveIds = _monitoredIds.length;
      FlutterForegroundTask.updateService(
        notificationTitle: 'Anti-Theft Active',
        notificationText: 'Monitoring $aliveIds devices',
      );
    } else if (action == 'rssi_update') {
      _processRssiUpdate(data);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    _stopContinuousAlarm();
    
    IsolateNameServer.removePortNameMapping('anti_theft_service_port');
    _receivePort?.close();
    
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    await _audioPlayer.dispose();
  }

  void _processRssiUpdate(Map<dynamic, dynamic> data) {
    final deviceId = data['device_id'] ?? '';
    final rawRssi = data['rssi'] ?? -90;
    final deviceName = data['device_name'] ?? 'Unknown';

    var deviceState = _deviceStates[deviceId] ?? _newState(deviceId, deviceName);
    List<int> buffer = List<int>.from(deviceState.rssiBuffer)..add(rawRssi);
    if (buffer.length > rssiBufferSize) buffer.removeAt(0);

    final smoothedRssi = _computeWeightedAverage(buffer);
    final consecutiveLow = smoothedRssi < _dynamicRssiFar ? deviceState.consecutiveLowReadings + 1 : 0;
    final nextState = _computeState(smoothedRssi, deviceState.state, consecutiveLow, deviceState.stateChangedAt);

    _deviceStates[deviceId] = deviceState.copyWith(
      smoothedRssi: smoothedRssi,
      rssiBuffer: buffer,
      state: nextState,
      stateChangedAt: nextState != deviceState.state ? DateTime.now().millisecondsSinceEpoch : deviceState.stateChangedAt,
      consecutiveLowReadings: consecutiveLow,
    );
  }

  int _computeWeightedAverage(List<int> readings) {
    if (readings.isEmpty) return -90;
    var weightedSum = 0;
    var totalWeight = 0;
    for (var i = 0; i < readings.length; i++) {
      final weight = i + 1;
      weightedSum += readings[i] * weight;
      totalWeight += weight;
    }
    return (weightedSum / totalWeight).round();
  }

  DeviceState _computeState(int rssi, DeviceState current, int lowReadings, int changedAt) {
    final now = DateTime.now().millisecondsSinceEpoch;
    int rssiSafe = _dynamicRssiFar + 5;

    if (rssi > rssiSafe) return DeviceState.safe;
    if (lowReadings >= alertCount) return DeviceState.alert;
    if (current == DeviceState.alert && now - changedAt < alertHoldMs) return DeviceState.alert;
    return DeviceState.warning;
  }

  DeviceProximityState _newState(String id, String name) {
    return DeviceProximityState(
      deviceId: id,
      deviceName: name,
      smoothedRssi: -90,
      rssiBuffer: [],
      state: DeviceState.safe,
      stateChangedAt: DateTime.now().millisecondsSinceEpoch,
      consecutiveLowReadings: 0,
    );
  }
}