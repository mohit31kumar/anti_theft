import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class DeviceSelectionScreen extends StatefulWidget {

  
  final List<ScanResult> devices;
  final Function(String, String) onSelect;
  

  const DeviceSelectionScreen({
    super.key,
    required this.devices,
    required this.onSelect,
  });
@override
State<DeviceSelectionScreen> createState() =>
    _DeviceSelectionScreenState();
}
Timer? refreshTimer;
class _DeviceSelectionScreenState
    extends State<DeviceSelectionScreen> {

  String getDistanceLabel(int rssi) {
    if (rssi > -60) return "Very Near";
    if (rssi > -75) return "Near";
    if (rssi > -85) return "Far";
    return "Very Far";
  }

  void runTest(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Move the device closer and watch signal strength"),
        duration: Duration(seconds: 2),
      ),
    );
  }



@override
void initState() {
  super.initState();

  refreshTimer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );
}




  @override
  Widget build(BuildContext context) {
    List<ScanResult> sortedDevices = List.from(widget.devices)
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(title: const Text("Select Device")),
      body: ListView.builder(
        itemCount: sortedDevices.length,
        itemBuilder: (context, index) {
          final device = sortedDevices[index].device;
          final rssi = sortedDevices[index].rssi;

          return Card(
            child: ListTile(
              title: Text(
                device.platformName.isNotEmpty
                    ? device.platformName
                    : "Device ${device.id.id.substring(0, 4)}",
              ),
              subtitle: Text("RSSI: $rssi | ${getDistanceLabel(rssi)}"),
              trailing: TextButton(
                onPressed: () => runTest(context),
                child: const Text("Test"),
              ),
              onTap: () {
                final name = device.platformName.isNotEmpty
                    ? device.platformName
                    : "Device ${device.id.id.substring(0, 4)}";

                widget.onSelect(device.id.id, name);
                Navigator.pop(context);
              },
            ),
          );
        },
      ),
    );
  }
  @override
void dispose() {
  refreshTimer?.cancel();
  super.dispose();
}
}
