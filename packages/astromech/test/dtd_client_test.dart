import 'package:astromech/src/dtd_client.dart';
import 'package:test/test.dart';

void main() {
  test('dtdUriFrom finds the address DevTools was started with', () {
    const processes = '''
/usr/bin/zsh
/sdk/bin/dart tooling-daemon --machine
/sdk/bin/dart devtools --machine --allow-embedding --dtd-uri ws://127.0.0.1:49290/8Z_KSMCGg7o=
''';

    expect(dtdUriFrom(processes), 'ws://127.0.0.1:49290/8Z_KSMCGg7o=');
    expect(dtdUriFrom('/usr/bin/zsh'), isNull);
  });

  test('parseDebugSessions reads id, name, device and VM service address', () {
    final sessions = parseDebugSessions({
      'debugSessions': [
        {
          'id': 'b48e',
          'name': 'snow_app_sit_debug (iPhone 17 Pro)',
          'flutterDeviceId': 'F37B',
          'vmServiceUri': 'ws://127.0.0.1:57622/9dKV=/ws',
        },
      ],
    });

    expect(sessions.single.id, 'b48e');
    expect(sessions.single.deviceId, 'F37B');
    expect(sessions.single.vmServiceUri, 'ws://127.0.0.1:57622/9dKV=/ws');
  });

  group('pickSession', () {
    const ours = DebugSession(id: 'a', name: 'snow', deviceId: 'SIM');
    const other = DebugSession(id: 'b', name: 'courier', deviceId: 'SIM');
    const elsewhere = DebugSession(id: 'c', name: 'snow', deviceId: 'PHONE');

    Future<bool> isOurs(DebugSession session) async => session.id == 'a';

    test('takes the only session on the device without probing', () async {
      final picked = await pickSession(
        [ours, elsewhere],
        device: 'SIM',
        isOurApp: (_) async => fail('no probe needed'),
      );

      expect(picked, ours);
    });

    test('probes when several sessions share the device', () async {
      expect(await pickSession([other, ours], device: 'SIM', isOurApp: isOurs), ours);
    });

    test('returns null when no session runs on the device', () async {
      expect(await pickSession([elsewhere], device: 'SIM', isOurApp: isOurs), isNull);
    });
  });
}
