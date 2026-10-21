import 'package:astromech/src/android.dart';
import 'package:astromech/src/simulator.dart';

/// No single device could be picked automatically.
class DeviceNotFoundException implements Exception {
  DeviceNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum DevicePlatform { ios, android }

/// The simulator, emulator or phone the app runs on.
class Device {
  const Device(this.id, this.platform, {this.name = ''});

  /// Simulator udid or adb serial - what mobilecli and the IDE call the device.
  final String id;
  final DevicePlatform platform;
  final String name;

  /// A PNG of the screen, without mobilecli.
  Future<void> screenshot(String path) => switch (platform) {
    DevicePlatform.ios => simulatorScreenshot(id, path),
    DevicePlatform.android => Adb(id).screenshot(path),
  };

  @override
  String toString() => name.isEmpty ? id : '$id ($name)';
}

/// Booted iOS simulators and running Android emulators / devices.
Future<List<Device>> runningDevices() async {
  final (simulators, android) = await (bootedSimulators(), Adb.devices()).wait;
  return [
    for (final s in simulators) Device(s.udid, DevicePlatform.ios, name: s.name),
    for (final a in android) Device(a.serial, DevicePlatform.android, name: a.model),
  ];
}

/// The device with [id], or the only running one - so no `--device` is needed in the usual setup.
Future<Device> pickDevice(String? id) async {
  final devices = await runningDevices();
  if (id != null) {
    // Not a booted simulator nor an adb device (e.g. a physical iPhone) - iOS, as before Android.
    return devices.where((d) => d.id == id).firstOrNull ?? Device(id, DevicePlatform.ios);
  }
  if (devices.length == 1) return devices.single;
  if (devices.isEmpty) {
    throw DeviceNotFoundException(
      'No booted simulator or running Android emulator / device - start one or pass --device.',
    );
  }
  throw DeviceNotFoundException('Several devices - pass --device: ${devices.join(', ')}');
}
