import 'dart:io';

/// `adb` on PATH, else the one in `$ANDROID_HOME` / `$ANDROID_SDK_ROOT` or the
/// default SDK location - IDEs and agents don't always inherit the shell's PATH.
final String adb = () {
  final env = Platform.environment;
  for (final sdk in [
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    '${env['HOME']}/Library/Android/sdk',
    '${env['HOME']}/Android/Sdk',
  ]) {
    if (sdk == null || sdk.isEmpty) continue;
    final candidate = File('$sdk/platform-tools/adb');
    if (candidate.existsSync()) return candidate.path;
  }
  return 'adb';
}();

/// Ready devices and emulators in `adb devices -l` output - offline and unauthorized
/// ones can't be driven.
List<({String serial, String model})> readyAdbDevices(String output) => [
  for (final line in output.split('\n').skip(1))
    if (line.trim().split(RegExp(r'\s+')) case [final serial, 'device', ...final details])
      (
        serial: serial,
        model:
            [
              for (final detail in details)
                if (detail.startsWith('model:')) detail.substring('model:'.length),
            ].firstOrNull ??
            '',
      ),
];

/// VM service addresses Flutter debug apps logged on the device (the port is the
/// device's), newest first, with the pid of the process that logged each.
List<({int pid, int port, String path})> vmServicesInLogcat(String logcat) {
  final pattern = RegExp(r'\(\s*(\d+)\): .*listening on http://[^:/\s]+:(\d+)(/\S*)?');
  return [
    for (final match in pattern.allMatches(logcat).toList().reversed)
      (
        pid: int.parse(match.group(1)!),
        port: int.parse(match.group(2)!),
        path: match.group(3) ?? '/',
      ),
  ];
}

/// The host port `adb forward --list` already maps to [devicePort] on [serial].
int? forwardedPort(String forwardList, String serial, int devicePort) {
  for (final line in forwardList.split('\n')) {
    if (line.trim().split(RegExp(r'\s+')) case [
      final s,
      final host,
      final device,
    ] when s == serial && device == 'tcp:$devicePort' && host.startsWith('tcp:')) {
      return int.tryParse(host.substring('tcp:'.length));
    }
  }
  return null;
}

/// One device or emulator, through `adb -s <serial>`.
class Adb {
  const Adb(this.serial);

  final String serial;

  /// Running devices and emulators; empty when there is no adb.
  static Future<List<({String serial, String model})>> devices() async {
    try {
      final result = await Process.run(adb, ['devices', '-l']);
      if (result.exitCode != 0) return const [];
      return readyAdbDevices(result.stdout as String);
    } on ProcessException {
      return const [];
    }
  }

  /// What Flutter logged so far (tag `flutter`), without waiting for more.
  Future<String> flutterLog() => _run(['logcat', '-d', '-v', 'brief', '-s', 'flutter']);

  /// The package a running process belongs to, or null when it is gone.
  Future<String?> processName(int pid) async {
    final result = await Process.run(adb, ['-s', serial, 'shell', 'cat', '/proc/$pid/cmdline']);
    if (result.exitCode != 0) return null;
    final name = (result.stdout as String).split('\x00').first.trim();
    return name.isEmpty ? null : name;
  }

  /// A host port forwarded to [devicePort] - the one `flutter run` set up when there is one.
  Future<int> forward(int devicePort) async {
    final existing = forwardedPort(await _run(['forward', '--list']), serial, devicePort);
    if (existing != null) return existing;
    return int.parse((await _run(['forward', 'tcp:0', 'tcp:$devicePort'])).trim());
  }

  /// A PNG of the screen, without mobilecli.
  Future<void> screenshot(String path) async {
    final result = await Process.run(adb, [
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (result.exitCode != 0) {
      throw ProcessException(
        adb,
        ['exec-out', 'screencap', '-p'],
        '${result.stderr}',
        result.exitCode,
      );
    }
    await File(path).writeAsBytes(result.stdout as List<int>);
  }

  Future<String> _run(List<String> args) async {
    final result = await Process.run(adb, ['-s', serial, ...args]);
    if (result.exitCode != 0) {
      throw ProcessException(adb, args, '${result.stderr}'.trim(), result.exitCode);
    }
    return result.stdout as String;
  }
}
