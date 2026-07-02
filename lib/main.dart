import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/splash_screen.dart';
import 'services/ble_task_handler.dart';
import 'services/persistence_service.dart'; // Ensure this file exists

@pragma('vm:entry-point')
void taskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(BleTaskHandler());
}

// Fixed: Added 'async' so we can use 'await'
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Define the missing helper method locally or call it directly
  _initForegroundTask();

  // Boot Recovery Logic
  bool shouldArm = await PersistenceService.isArmed();
  if (shouldArm) {
    // Note: canStartService was replaced by checkNotificationPermission in recent versions
    NotificationPermission permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.granted) {
      FlutterForegroundTask.startService(
        notificationTitle: 'Anti-Theft Restarted',
        notificationText: 'Resuming protection...',
        callback: taskEntryPoint,
      );
    }
  }

  runApp(const MyApp());
}

// The missing initialization helper
void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'anti_theft',
      channelName: 'Anti Theft Service',
      channelDescription: 'Monitoring BLE devices',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions( // Removed 'const' to allow dynamic types
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      // Removed 'const' from SplashScreen if its constructor isn't const
      home: SplashScreen() 
    );
  }
}