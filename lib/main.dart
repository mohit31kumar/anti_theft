import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'dart:async';
// import 'dart:typed_data';

// void main() {
//   runApp(const AntiTheftApp());
// }

// class AntiTheftApp extends StatelessWidget {
//   const AntiTheftApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       home: DashboardScreen(),
//     );
//   }
// }

// class DashboardScreen extends StatefulWidget {
//   @override
//   State<DashboardScreen> createState() => _DashboardScreenState();
// }

// class _DashboardScreenState extends State<DashboardScreen> {
//   Timer? monitorTimer;
//   bool isSafe = true;
//   bool wasSafe = true;
//   String? targetDeviceId;
//   List<ScanResult> foundDevices = [];

//   // Local notifications plugin instance
//   final FlutterLocalNotificationsPlugin notificationsPlugin =
//       FlutterLocalNotificationsPlugin();
//   //  Audio player instance
//   final AudioPlayer player = AudioPlayer();
//   // Function to play alarm sound

//   // Monitoring timer and state variables

//   @override
//   void initState() {
//     super.initState();
//     startBluetoothScan();
//     initNotifications();
//     requestPermissions();

//     FlutterBluePlus.isScanning.listen((scanning) async {
//   if (!scanning) {
//     await Future.delayed(const Duration(seconds: 2));
//     startBluetoothScan();
//   }
// });
//     // Start monitoring timer
//     monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
//       setState(() {
//         // isSafe = !isSafe;
//       });

//       // Only trigger when going SAFE → ALERT
//       if (wasSafe && !isSafe) {
//         showMonitoringNotification();
//         showAlertNotification();
//         playAlarm();
//       }

//       wasSafe = isSafe;
//     });
//   }

//   Future<void> requestPermissions() async {
//     await Permission.bluetoothScan.request();
//     await Permission.bluetoothConnect.request();
//     await Permission.location.request();

//     if (await Permission.bluetoothScan.isPermanentlyDenied) {
//   openAppSettings();
// }

//   }

//   Future<void> initNotifications() async {
//     const AndroidInitializationSettings androidSettings =
//         AndroidInitializationSettings('@mipmap/ic_launcher');

//     const InitializationSettings settings = InitializationSettings(
//       android: androidSettings,
//     );

//     await notificationsPlugin.initialize(settings);
//     notificationsPlugin
//         .resolvePlatformSpecificImplementation<
//           AndroidFlutterLocalNotificationsPlugin
//         >()
//         ?.requestNotificationsPermission();
//   }

//   Future<void> startBluetoothScan() async {
//     print("Starting Bluetooth Scan");

//     await FlutterBluePlus.stopScan();

//     await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

//     FlutterBluePlus.scanResults.listen((results) {
//       print("Results length: ${results.length}");

//       setState(() {
//         foundDevices = List.from(results);
//       });

//       for (ScanResult r in results) {
//         print("Device: ${r.device.id.id} RSSI: ${r.rssi}");

//         if (targetDeviceId != null && r.device.id.id == targetDeviceId) {
//           checkProximity(r.rssi);
//         }
//       }
//     });
//   }

//   // Function to check proximity based on RSSI
//   void checkProximity(int rssi) {
//     print("Checking RSSI: $rssi");

//     if (rssi < -75 && isSafe) {
//       print("ALERT TRIGGERED");
//       setState(() => isSafe = false);
//       showMonitoringNotification();
//       showAlertNotification();
//       playAlarm();
//     }

//     if (rssi > -70 && !isSafe) {
//       print("SAFE AGAIN");
//       setState(() => isSafe = true);
//     }
//   }

//   // Function to show alert notification
//   Future<void> showAlertNotification() async {
//     final AndroidNotificationDetails androidDetails =
//         AndroidNotificationDetails(
//           'alert_channel',
//           'Alerts',
//           importance: Importance.max,
//           priority: Priority.high,
//           enableVibration: true,
//           fullScreenIntent: true,
//           vibrationPattern: Int64List.fromList([0, 1200, 300, 1200]),
//         );

//     final NotificationDetails details = NotificationDetails(
//       android: androidDetails,
//     );

//     await notificationsPlugin.show(
//       0,
//       "Theft Alert!",
//       "Device moved out of safe range",
//       details,
//     );
//   }

//   Future<void> playAlarm() async {
//     await player.play(AssetSource('sounds/alarm.mp3'));
//   }

//   // Function to open device selector dialog
//   void openDeviceSelector() {
//     showDialog(
//       context: context,
//       builder: (_) => AlertDialog(
//         title: Text("Choose Device"),
//         content: SizedBox(
//           width: double.maxFinite,
//           child: ListView.builder(
//             itemCount: foundDevices.length,
//             itemBuilder: (context, index) {
//               final device = foundDevices[index].device;
//               return ListTile(
//                 title: Text(
//                   device.platformName.isNotEmpty
//                       ? device.platformName
//                       : "Device ${device.id.id.substring(0, 5)}",
//                 ),

//                 subtitle: Text("RSSI: ${foundDevices[index].rssi}"),

//                 onTap: () {
//                   setState(() {
//                     targetDeviceId = device.id.id;
//                   });

//                   FlutterBluePlus.startScan(
//                     timeout: const Duration(seconds: 0),
//                   ); // continuous
//                   Navigator.pop(context);
//                 },
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }

//      // Function to show monitoring notification
//     Future<void> showMonitoringNotification() async {
//       const AndroidNotificationDetails androidDetails =
//           AndroidNotificationDetails(
//             'monitor_channel',
//             'Monitoring',
//             importance: Importance.low,
//             priority: Priority.low,
//             ongoing: true,
//             autoCancel: false,
//             showWhen: false,
//           );

//       const NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//       );

//       await notificationsPlugin.show(
//         1,
//         "Anti-Theft Active",
//         "Monitoring device proximity...",
//         details,
//       );
//     }


//   // Cancel the timer when the widget is disposed
//   @override
//   void dispose() {
//     notificationsPlugin.cancel(1);
//     monitorTimer?.cancel();
//     super.dispose();
//   }

//   @override
//   // Build the main dashboard UI
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Anti-Theft Proximity"),
//         centerTitle: true,
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             Text(
//               "CURRENT STATUS",
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 14,
//                 letterSpacing: 1.2,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//             Text(targetDeviceId ?? "No device selected"),
//             SizedBox(height: 12),
//             Text(
//               isSafe ? "SAFE STATE" : "THEFT ALERT",
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 13,
//                 fontWeight: FontWeight.w600,
//                 letterSpacing: 1.1,
//               ),
//             ),
//             SizedBox(height: 8),
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: isSafe ? Colors.green.shade100 : Colors.red.shade100,
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // Monitoring Status
//                   Text(
//                     "Monitoring Active...",
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: Colors.black54,
//                       fontStyle: FontStyle.italic,
//                     ),
//                   ),

//                   SizedBox(height: 6),
//                   SizedBox(
//                     width: 16,
//                     height: 16,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   ),
//                   SizedBox(height: 8),

//                   // Status Icon and Message
//                   Icon(
//                     isSafe ? Icons.security : Icons.warning_rounded,
//                     color: isSafe ? Colors.green : Colors.red,
//                   ),
//                   SizedBox(height: 12),
//                   Text(
//                     isSafe ? "DEVICE SAFE" : "THEFT ALERT",
//                     style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//                   ),
//                   SizedBox(height: 6),
//                   Text(
//                     isSafe
//                         ? "No suspicious activity detected"
//                         : "Device moved out of safe range",
//                   ),
//                   SizedBox(height: 8),
//                   Text(
//                     "Last checked: ${TimeOfDay.now().format(context)}",
//                     style: TextStyle(fontSize: 12, color: Colors.black54),
//                   ),
//                 ],
//               ),
//             ),
//             SizedBox(height: 24),
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: () {
//                   setState(() {
//                     isSafe = !isSafe;
//                   });
//                 },
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: isSafe ? Colors.red : Colors.green,
//                   padding: EdgeInsets.symmetric(vertical: 14),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                 ),

//                 child: Text(
//                   isSafe ? "Stop Monitoring" : "Start Monitoring",
//                   style: TextStyle(fontSize: 16),
//                 ),
//               ),
//             ),
//             SizedBox(height: 10),
//             ElevatedButton(
//               onPressed: openDeviceSelector,
//               child: Text("Select Device"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


// //////////////////////////////////////////////////////////////////////////////////////////////////

  
//   //   // function to start Bluetooth scanning
//   //   Future<void> startBluetoothScan() async {
//   //     await Permission.location.request();
//   //     await Permission.bluetoothScan.request();
//   //     await Permission.bluetoothConnect.request();
//   //     print(await Permission.bluetoothScan.status);
//   //     await FlutterBluePlus.stopScan();
//   //     print("Starting Bluetooth Scan...");
//   //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 0));

//   //     FlutterBluePlus.scanResults.listen((results) {
//   //       setState(() {
//   //         foundDevices = results;
//   //       });

//   //       for (ScanResult r in results) {
//   //         if (targetDeviceId != null && r.device.id.id == targetDeviceId) {
//   //           checkProximity(r.rssi);
//   //         }
//   //       }
//   //     });
//   //   }

//   //   // Function to show monitoring notification
//   //   Future<void> showMonitoringNotification() async {
//   //     const AndroidNotificationDetails androidDetails =
//   //         AndroidNotificationDetails(
//   //           'monitor_channel',
//   //           'Monitoring',
//   //           importance: Importance.low,
//   //           priority: Priority.low,
//   //           ongoing: true,
//   //           autoCancel: false,
//   //           showWhen: false,
//   //         );

//   //     const NotificationDetails details = NotificationDetails(
//   //       android: androidDetails,
//   //     );

//   //     await notificationsPlugin.show(
//   //       1,
//   //       "Anti-Theft Active",
//   //       "Monitoring device proximity...",
//   //       details,
//   //     );
//   //   }

    

    
//   //   // Initialize local notifications
//   //   const AndroidInitializationSettings androidSettings =
//   //       AndroidInitializationSettings('@mipmap/ic_launcher');

//   //   const InitializationSettings settings = InitializationSettings(
//   //     android: androidSettings,
//   //   );

//   //   notificationsPlugin.initialize(settings);
//   //   // Request notification permissions (for Android 13+)
//   //   notificationsPlugin
//   //       .resolvePlatformSpecificImplementation<
//   //         AndroidFlutterLocalNotificationsPlugin
//   //       >()
//   //       ?.requestNotificationsPermission();

//   //   // Function to trigger vibration
//   //   // Future<void> vibrateNow() async {
//   //   //   if (await Vibration.hasVibrator() ?? false) {
//   //   //     Vibration.vibrate(duration: 800);
//   //   //   }
//   //   // }

//   //   // Start monitoring timer
//   //   monitorTimer = Timer.periodic(Duration(seconds: 3), (timer) {
//   //     setState(() {
//   //       // isSafe = !isSafe;
//   //     });

//   //     // Only trigger when going SAFE → ALERT
//   //     if (wasSafe && !isSafe) {
//   //       // vibrateNow();
//   //       showMonitoringNotification();
//   //       showAlertNotification();
//   //       playAlarm();
//   //     }

//   //     wasSafe = isSafe;
//   //   });
//   // }

