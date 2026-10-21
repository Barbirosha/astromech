import 'package:astromech/src/android.dart';
import 'package:test/test.dart';

void main() {
  test('readyAdbDevices skips offline and unauthorized devices', () {
    const output = '''
List of devices attached
emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
emulator-5556          offline transport_id:2
R5CT1234ABC            unauthorized usb:1-1 transport_id:3
0A091FDD4000AB         device usb:1-2 product:husky model:Pixel_8_Pro device:husky transport_id:4

''';

    expect(readyAdbDevices(output), [
      (serial: 'emulator-5554', model: 'sdk_gphone64_arm64'),
      (serial: '0A091FDD4000AB', model: 'Pixel_8_Pro'),
    ]);
  });

  test('readyAdbDevices is empty when nothing is attached', () {
    expect(readyAdbDevices('List of devices attached\n\n'), isEmpty);
  });

  test('vmServicesInLogcat lists logged addresses newest first', () {
    const logcat = '''
--------- beginning of main
I/flutter ( 4321): The Dart VM service is listening on http://127.0.0.1:37421/abc123=/
I/flutter ( 4321): hello from the app
I/flutter ( 5678): The Dart VM service is listening on http://127.0.0.1:41003/xyz-_=/
''';

    expect(vmServicesInLogcat(logcat), [
      (pid: 5678, port: 41003, path: '/xyz-_=/'),
      (pid: 4321, port: 37421, path: '/abc123=/'),
    ]);
  });

  test('forwardedPort finds the host port of an existing forward on this device', () {
    const list = '''
emulator-5554 tcp:52001 tcp:37421
emulator-5556 tcp:52002 tcp:41003
''';

    expect(forwardedPort(list, 'emulator-5554', 37421), 52001);
    expect(forwardedPort(list, 'emulator-5554', 41003), isNull);
  });
}
