import 'package:astromech/src/simulator.dart';
import 'package:test/test.dart';

void main() {
  test('bootedDevices lists only booted simulators across runtimes', () {
    const json = '''
{"devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
    {"udid": "A", "name": "iPhone 17 Pro", "state": "Booted"},
    {"udid": "B", "name": "iPhone 16", "state": "Shutdown"}
  ],
  "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
    {"udid": "C", "name": "iPad", "state": "Booted"}
  ]
}}''';

    expect(bootedDevices(json).map((d) => d.udid), ['A', 'C']);
  });

  test('bootedDevices is empty when nothing is booted', () {
    expect(bootedDevices('{"devices": {}}'), isEmpty);
  });
}
