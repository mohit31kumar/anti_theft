import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:anti_theft/screens/device_selection_screen.dart';

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
  Timer? monitorTimer;
  bool isSafe = true;
  bool wasSafe = true;
  Map<String, MonitoredDevice> monitoredDevices = {};

  List<ScanResult> foundDevices = [];

  // Local notifications plugin instance
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  //  Audio player instance
  final AudioPlayer player = AudioPlayer();

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      // 1. Ask permissions FIRST
      await requestPermissions();

      // 2. Initialize notifications
      await initNotifications();

      // 3. Start Bluetooth scan safely
      await startBluetoothScan();

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

  // Function to remove a monitored device
  void removeDevice(String id) {
    setState(() {
      monitoredDevices.remove(id);
    });

    if (monitoredDevices.isEmpty) {
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
                  setState(() {
                    monitoredDevices[device.id.id] = MonitoredDevice(
                      id: device.id.id,
                      name: device.platformName.isNotEmpty
                          ? device.platformName
                          : "Device ${device.id.id.substring(0, 4)}",
                    );
                  });

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
      999, // unique ID for monitoring notification
      "Anti-Theft Active",
      "Monitoring ${monitoredDevices.length} devices",
      notificationDetails,
    );
  }

  // Stop Monitoring Notification
  Future<void> stopMonitoringNotification() async {
    await notificationsPlugin.cancel(999);
  }

  // Cancel the timer when the widget is disposed
  @override
  void dispose() {
    notificationsPlugin.cancel(1);
    monitorTimer?.cancel();
    super.dispose();
  }

  @override
  // Build the main dashboard UI
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Anti-Theft Proximity"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "CURRENT STATUS",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                monitoredDevices.isEmpty
                    ? "No device selected"
                    : "Monitoring ${monitoredDevices.length} devices",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Column(
              children: monitoredDevices.values.map((d) {
                return Card(
                  child: ListTile(
                    title: Text(d.alias ?? d.name),
                    subtitle: Text(d.isSafe ? "SAFE" : "ALERT"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => renameDevice(d),
                        ),

                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => removeDevice(d.id),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            SizedBox(height: 12),
            Text(
              isSafe ? "SAFE STATE" : "THEFT ALERT",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isSafe ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Monitoring Status
                  Text(
                    "Monitoring Active...",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  SizedBox(height: 6),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 8),

                  // Status Icon and Message
                  Icon(
                    isSafe ? Icons.security : Icons.warning_rounded,
                    color: isSafe ? Colors.green : Colors.red,
                  ),
                  SizedBox(height: 12),
                  Text(
                    isSafe ? "DEVICE SAFE" : "THEFT ALERT",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    isSafe
                        ? "No suspicious activity detected"
                        : "Device moved out of safe range",
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Last checked: ${TimeOfDay.now().format(context)}",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceSelectionScreen(
                      devices: foundDevices,
                      onSelect: (id, name) {
                        setState(() {
                          monitoredDevices[id] = MonitoredDevice(
                            id: id,
                            name: name,
                          );
                        });

                        startMonitoringTimer();

                        showMonitoringNotification(); // 👈 add here
                      },
                    ),
                  ),
                );
              },
              child: const Text("Select Device"),
            ),

            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: monitoredDevices.isEmpty
                    ? null
                    : () {
                        setState(() {
                          isSafe = !isSafe;
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSafe ? Colors.red : Colors.green,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                child: Text(
                  isSafe ? "Stop Monitoring" : "Start Monitoring",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
