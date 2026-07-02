import 'package:flutter/material.dart';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:typed_data';
// import 'package:anti_theft/screens/device_selection_screen.dart';
// import 'package:anti_theft/services/ble_task_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:anti_theft/main.dart' show taskEntryPoint;
import 'package:anti_theft/services/persistence_service.dart';

class MonitoredDevice {
  String id;
  String name;
  String? alias;
  bool isSafe;
  int lastRssi;

  MonitoredDevice({
    required this.id,
    required this.name,
    this.alias,
    this.isSafe = true,
    this.lastRssi = -60,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _servicePortName = 'anti_theft_service_port';

  Timer? monitorTimer;
  bool isSafe = true;
  bool wasSafe = true;
  double _currentDistanceThreshold = 5.0; // Default 5 meters
  Map<String, MonitoredDevice> monitoredDevices = {};
  Set<String> _allDeviceIds = {};

  List<ScanResult> foundDevices = [];

  // Local notifications plugin instance
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  //  Audio player instance
  final AudioPlayer player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadSavedThreshold();
    _loadSavedDevices();

    Future.microtask(() async {
      // 1. Ask permissions FIRST
      await requestPermissions();

      // 2. Initialize notifications
      await initNotifications();

      // 3. Start Bluetooth scan safely
      // await startBluetoothScan();

      // 4. Auto-restart scan if it stops
      FlutterBluePlus.isScanning.listen((scanning) async {
        if (!scanning) {
          print("Scan stopped → restarting");
          await Future.delayed(const Duration(seconds: 2));
          await startBluetoothScan();
        }
      });
    });
  }

  Future<void> _loadSavedDevices() async {
    List<String> visibleIds = await PersistenceService.getVisibleDeviceIds();
    List<String> allIds = await PersistenceService.getAllDeviceIds();

    if (allIds.isEmpty && visibleIds.isNotEmpty) {
      allIds = List.from(visibleIds);
      await PersistenceService.saveAllDeviceIds(allIds);
    }

    setState(() {
      for (String id in visibleIds) {
        monitoredDevices[id] = MonitoredDevice(
          id: id,
          name: "Device ${id.substring(0, 4)}",
        );
      }
      _allDeviceIds = Set<String>.from(allIds);
    });
  }

  // Function to rename a monitored device
  void renameDevice(MonitoredDevice device) {
    TextEditingController controller = TextEditingController(
      text: device.alias ?? device.name,
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Rename Device"),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                device.alias = controller.text;
              });
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // Function to remove a monitored device from UI only (keeps monitoring in background)
  void removeDevice(String id) {
    setState(() {
      monitoredDevices.remove(id);
    });

    PersistenceService.saveVisibleDeviceIds(monitoredDevices.keys.toList());

    if (_allDeviceIds.isNotEmpty) {
      showMonitoringNotification();
    } else {
      stopMonitoringNotification();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hidden from view. Device is still monitored in the background.')),
      );
    }
  }

  // Function to fully forget a device (stops monitoring permanently)
  Future<void> forgetDevice(String id) async {
    setState(() {
      monitoredDevices.remove(id);
      _allDeviceIds.remove(id);
    });

    await PersistenceService.saveVisibleDeviceIds(monitoredDevices.keys.toList());
    await PersistenceService.saveAllDeviceIds(_allDeviceIds.toList());

    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      _servicePortName,
    );
    sendPort?.send({
      'action': 'remove_device',
      'device_id': id,
    });

    if (monitoredDevices.isEmpty && _allDeviceIds.isEmpty) {
      stopMonitoringNotification();
    }
  }

  // Start monitoring timer
  void startMonitoringTimer() {
    monitorTimer?.cancel();

    monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // 🚨 IMPORTANT GUARD
      if (monitoredDevices.isEmpty) return;

      setState(() {});

      if (wasSafe && !isSafe) {
        showMonitoringNotification();
        // showAlertNotification( device.name);
        playAlarm();
      }

      wasSafe = isSafe;
    });
  }

  Future<void> requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();

    if (await Permission.bluetoothScan.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  // Request permissions BEFORE starting foreground service (Android 14+)
  Future<void> requestBlePermissions() async {
    final results = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!results[Permission.bluetoothScan]!.isGranted ||
        !results[Permission.bluetoothConnect]!.isGranted ||
        !results[Permission.location]!.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Required BLE permissions not granted')),
        );
      }
      throw Exception("BLE permissions not granted");
    }
  }

  Future<void> initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await notificationsPlugin.initialize(settings);
    notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> startBluetoothScan() async {
    try {
      print("Starting Bluetooth Scan");

      // 1. Check Bluetooth state
      var state = await FlutterBluePlus.adapterState.first;

      if (state != BluetoothAdapterState.on) {
        print("Bluetooth OFF → requesting enable");

        await FlutterBluePlus.turnOn();

        // Wait until Bluetooth actually turns ON
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first;
      }

      // 2. Prevent duplicate scans
      if (await FlutterBluePlus.isScanning.first) {
        print("Scan already running");
        return;
      }

      // 3. Start scan
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      // 4. Listen to results
      FlutterBluePlus.scanResults.listen((results) {
        print("Devices Found: ${results.length}");

        setState(() {
          foundDevices = List.from(results);
        });

        for (ScanResult r in results) {
          print("Device: ${r.device.id.id} RSSI: ${r.rssi}");

          String id = r.device.id.id;

          if (monitoredDevices.containsKey(id)) {
            monitoredDevices[id]!.lastRssi = r.rssi;
            checkProximity(id, r.rssi);
            _sendRssiToBackgroundService(id, r.rssi);
          }
        }
      });
    } catch (e) {
      print("Scan Error: $e");
    }
  }

  // Function to check proximity based on RSSI
  void checkProximity(String id, int rssi) {
    var device = monitoredDevices[id]!;

    if (rssi < -75 && device.isSafe) {
      device.isSafe = false;
      showAlertNotification(device.name);
      playAlarm();
    }

    if (rssi > -70 && !device.isSafe) {
      device.isSafe = true;
    }
  }

  Future<void> _sendRssiToBackgroundService(String deviceId, int rssi) async {
    try {
      final SendPort? sendPort = IsolateNameServer.lookupPortByName(
        _servicePortName,
      );
      sendPort?.send({
        'action': 'rssi_update',
        'device_id': deviceId,
        'rssi': rssi,
        'device_name': monitoredDevices[deviceId]?.name ?? 'Unknown',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print("RSSI send error: $e");
    }
  }

  // Function to show alert notification
  Future<void> showAlertNotification(String deviceName) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'alert_channel',
          'Alerts',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          fullScreenIntent: true,
          vibrationPattern: Int64List.fromList([0, 1200, 300, 1200]),
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await notificationsPlugin.show(
      0,
      "Theft Alert!",
      "Device ${deviceName} moved out of safe range",
      details,
    );
  }

  Future<void> playAlarm() async {
    await player.play(AssetSource('sounds/alarm.mp3'));
  }

  // Add a device to both visible and all-device lists, then persist
  void addDevice(String id, String name) {
    setState(() {
      monitoredDevices[id] = MonitoredDevice(
        id: id,
        name: name.isNotEmpty ? name : "Device ${id.substring(0, 4)}",
      );
      _allDeviceIds.add(id);
    });

    PersistenceService.saveVisibleDeviceIds(monitoredDevices.keys.toList());
    PersistenceService.saveAllDeviceIds(_allDeviceIds.toList());

    // If service is running, forward the new device ID to background
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      _servicePortName,
    );
    sendPort?.send({
      'action': 'add_device',
      'device_id': id,
      'device_name': name.isNotEmpty ? name : "Device ${id.substring(0, 4)}",
    });
  }

  // Function to open device selector dialog
  void openDeviceSelector() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Choose Device"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: foundDevices.length,
            itemBuilder: (context, index) {
              final device = foundDevices[index].device;
              return ListTile(
                title: Text(
                  device.platformName.isNotEmpty
                      ? device.platformName
                      : "Device ${device.id.id.substring(0, 5)}",
                ),

                subtitle: Text("RSSI: ${foundDevices[index].rssi}"),

                onTap: () {
                  addDevice(device.id.id, device.platformName);

                  FlutterBluePlus.startScan(
                    timeout: const Duration(seconds: 0),
                  ); // continuous
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // Function to show monitoring notification
  Future<void> showMonitoringNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'monitor_channel',
          'Monitoring Service',
          channelDescription: 'Anti-Theft monitoring active',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // 🔒 cannot swipe away
          autoCancel: false,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await notificationsPlugin.show(
      999,
      "Anti-Theft Active",
      "Monitoring ${_allDeviceIds.isNotEmpty ? _allDeviceIds.length : monitoredDevices.length} ${(_allDeviceIds.isNotEmpty ? _allDeviceIds.length : monitoredDevices.length) == 1 ? 'device' : 'devices'}",
      notificationDetails,
    );
  }

  // Stop Monitoring Notification
  Future<void> stopMonitoringNotification() async {
    await notificationsPlugin.cancel(999);
  }

  // Start monitoring service with proper permission and state checks (Android 14+ compatible)
  Future<void> startMonitoringService() async {
    try {
      // ✅ STEP 1: Request all permissions FIRST
      await requestBlePermissions();

      // ✅ STEP 2: Handle Battery Optimizations
      // On modern Android (API 30+), background scans are heavily throttled
      // unless the app is explicitly whitelisted.
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        // In version 6.5.0, this opens the system dialog for the user.
        await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
      }

      // ✅ STEP 3: Check if already running
      bool isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Service already running')),
          );
        }
        return;
      }

      // ✅ STEP 4: PERSISTENCE HANDSHAKE (CRITICAL)
      // We save the "Armed" state and the device list to disk so the
      // background isolate can load them independently upon starting.
      await PersistenceService.setArmed(true);
      await PersistenceService.saveVisibleDeviceIds(
        monitoredDevices.keys.toList(),
      );
      await PersistenceService.saveAllDeviceIds(
        _allDeviceIds.toList(),
      );

      // ✅ STEP 5: Start service with proper callback
      bool success = await FlutterForegroundTask.startService(
        notificationTitle: 'Anti-Theft Active',
        notificationText: 'Monitoring ${_allDeviceIds.length} ${_allDeviceIds.length == 1 ? 'device' : 'devices'}',
        callback:
            taskEntryPoint, // Uses the @pragma function from main.dart[cite: 1]
      );

      if (success) {
        setState(() {
          // UI state update can go here[cite: 1]
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Background monitoring started')),
          );
        }
        print("✅ Foreground service started successfully");
      } else {
        throw Exception("Failed to start foreground service");
      }
    } catch (e) {
      print("❌ Error starting service: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // Function to update threshold in the background service
  Future<void> _loadSavedThreshold() async {
    double saved = await PersistenceService.getThresholdDistance();
    setState(() {
      _currentDistanceThreshold = saved;
    });
  }

  // Cancel the timer when the widget is disposed
  @override
  void dispose() {
    notificationsPlugin.cancel(1);
    monitorTimer?.cancel();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light professional grey
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          "Security Hub",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching, color: Colors.blue),
            onPressed: startBluetoothScan,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildMainStatusRing(), // The core visual state
              const SizedBox(height: 30),
              _buildServiceControlCard(), // One-tap service activation
              const SizedBox(height: 20),
              
              // ✅ FIXED: Added the slider to the screen!
              _buildSensitivitySlider(), 
              
              const SizedBox(height: 10),
              _buildDeviceListHeader(),
              _buildDeviceGrid(), // Modern list of tracked items
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openDeviceSelector,
        label: const Text("Add Device"),
        icon: const Icon(Icons.add_moderator),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Widget _buildMainStatusRing() {
    final Color statusColor = isSafe ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusColor.withOpacity(0.05),
        border: Border.all(color: statusColor.withOpacity(0.2), width: 2),
      ),
      child: Column(
        children: [
          Icon(
            isSafe ? Icons.shield_outlined : Icons.gpp_maybe,
            size: 80,
            color: statusColor,
          ),
          const SizedBox(height: 10),
          Text(
            isSafe ? "SYSTEM SECURE" : "THEFT DETECTED",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: statusColor,
              letterSpacing: 1.5,
            ),
          ),
          Text(
            _allDeviceIds.isEmpty
                ? "No active guards"
                : "${_allDeviceIds.length} ${_allDeviceIds.length == 1 ? 'device' : 'devices'} under watch",
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceControlCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.blue,
            child: Icon(Icons.run_circle_outlined, color: Colors.white),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Background Protection",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "Stay armed even if app is closed",
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isSafe, // Bind this to your 'isServiceRunning' check
            onChanged: (val) async {
              if (val) await startMonitoringService();
              // Logic to stop service if toggled off
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSensitivitySlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Detection Range",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                "${_currentDistanceThreshold.toStringAsFixed(1)} m",
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Slider(
            value: _currentDistanceThreshold,
            min: 1.0,
            max: 20.0,
            divisions: 19,
            activeColor: Colors.blue,
            inactiveColor: Colors.blue.withOpacity(0.2),
            onChanged: (double value) {
              setState(() {
                _currentDistanceThreshold = value;
              });
            },
            onChangeEnd: (double value) async {
              // 1. Save to disk for background isolate persistence
              await PersistenceService.setThresholdDistance(value);
              
              // 2. Use native Isolate port to send data (Bulletproof method)
              final SendPort? sendPort = IsolateNameServer.lookupPortByName('anti_theft_service_port');
              
              if (sendPort != null) {
                sendPort.send({
                  'action': 'update_threshold',
                  'value': value,
                });
                print("Threshold update sent via Isolate: $value m");
              } else {
                print("Service not running, but threshold saved.");
              }
            },
          ),
          const Text(
            "Decreasing distance makes the alarm more sensitive.",
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceListHeader() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(Icons.devices, size: 18, color: Colors.black54),
          SizedBox(width: 8),
          Text(
            "MONITORED DEVICES",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGrid() {
    if (monitoredDevices.isEmpty) {
      return Container(
        height: 100,
        width: double.infinity,
        alignment: Alignment.center,
        child: const Text(
          "Tap '+' to add a device to protect",
          style: TextStyle(color: Colors.black38),
        ),
      );
    }

    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: monitoredDevices.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            var d = monitoredDevices.values.elementAt(index);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.watch,
                  color: d.isSafe ? Colors.blue : Colors.red,
                ),
                title: Text(
                  d.alias ?? d.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Signal: ${d.lastRssi} dBm",
                  style: TextStyle(
                    color: d.lastRssi < -75 ? Colors.orange : Colors.green,
                  ),
                ),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Text("Rename"),
                      onTap: () =>
                          Future.delayed(Duration.zero, () => renameDevice(d)),
                    ),
                    PopupMenuItem(
                      child: const Text("Remove from View"),
                      onTap: () => removeDevice(d.id),
                    ),
                    PopupMenuItem(
                      child: const Text(
                        "Forget Permanently",
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      onTap: () => forgetDevice(d.id),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (_allDeviceIds.length > monitoredDevices.length)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(Icons.visibility_off, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Text(
                  "${_allDeviceIds.length - monitoredDevices.length} device(s) hidden but still monitored",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
