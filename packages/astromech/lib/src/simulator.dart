import 'dart:convert';
import 'dart:io';

/// Booted iOS simulators; empty when there is no Xcode.
Future<List<({String udid, String name})>> bootedSimulators() async {
  try {
    final result = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted', '-j']);
    if (result.exitCode != 0) return const [];
    return bootedDevices(result.stdout as String);
  } on ProcessException {
    return const [];
  }
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
