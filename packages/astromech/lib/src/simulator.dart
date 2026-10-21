import 'dart:convert';
import 'dart:io';

/// No single device could be picked automatically.
class DeviceNotFoundException implements Exception {
  DeviceNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The one booted iOS simulator - so no `--device` is needed in the usual setup.
Future<String> bootedSimulator() async {
  final result = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted', '-j']);
  if (result.exitCode != 0) {
    throw DeviceNotFoundException('xcrun simctl failed: ${result.stderr}'.trim());
  }
  final booted = bootedDevices(result.stdout as String);
  if (booted.length == 1) return booted.single.udid;
  if (booted.isEmpty) {
    throw DeviceNotFoundException('No booted simulator - boot one or pass --device.');
  }
  throw DeviceNotFoundException(
    'Several booted simulators - pass --device: '
    '${booted.map((d) => '${d.udid} (${d.name})').join(', ')}',
  );
}

/// Booted devices in `xcrun simctl list devices booted -j` output.
List<({String udid, String name})> bootedDevices(String simctlJson) {
  final json = jsonDecode(simctlJson) as Map<String, dynamic>;
  final runtimes = json['devices'] as Map<String, dynamic>? ?? const {};
  return [
    for (final devices in runtimes.values.cast<List<dynamic>>())
      for (final device in devices.cast<Map<String, dynamic>>())
        if (device['state'] == 'Booted')
          (udid: device['udid'] as String, name: device['name'] as String? ?? ''),
  ];
}

/// A PNG of the simulator screen, without mobilecli.
Future<void> simulatorScreenshot(String udid, String path) async {
  final result = await Process.run('xcrun', ['simctl', 'io', udid, 'screenshot', path]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'xcrun',
      ['simctl', 'io', udid, 'screenshot'],
      '${result.stderr}',
      result.exitCode,
    );
  }
}
