import 'dart:io';

import 'package:astromech/src/flow_library.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('summarizeFlow', () {
    test('reads the title, precondition and app from the header', () {
      const content = '''
# Round Cover: Covered filter shows only covered rounds.
# Precondition: snow_app is open on the Dashboard, logged in.
# No terminate/launch: a relaunch drops code.
app: com.parcelscloud.apps.snow
steps:
  - tap: { id: button_filter }
  # A comment between steps is not the title.
''';

      final summary = summarizeFlow('flows/snow/covered.yaml', content);

      expect(summary.title, 'Round Cover: Covered filter shows only covered rounds.');
      expect(summary.precondition, 'snow_app is open on the Dashboard, logged in.');
      expect(summary.app, 'com.parcelscloud.apps.snow');
    });

    test('joins a title spread over several comment lines', () {
      const content = '''
# Round Cover: the "Uncovered" filter leaves only uncovered rounds
# and shows a "Filter: Uncovered" chip.
# Precondition: Dashboard.
# No terminate/launch.
steps: []
''';

      final summary = summarizeFlow('x.yaml', content);

      expect(
        summary.title,
        'Round Cover: the "Uncovered" filter leaves only uncovered rounds '
        'and shows a "Filter: Uncovered" chip.',
      );
    });

    test('marks a flow without a header comment', () {
      final summary = summarizeFlow('x.yaml', 'steps:\n  - tap: { id: a }\n');

      expect(summary.title, '(no description)');
      expect(summary.precondition, isNull);
    });
  });

  test('listFlows finds yaml files recursively, sorted', () {
    final root = Directory.systemTemp.createTempSync('flows');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/snow/b.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('# B\nsteps: []\n');
    File('${root.path}/snow/a.yaml').writeAsStringSync('# A\nsteps: []\n');
    File('${root.path}/snow/notes.txt').writeAsStringSync('ignored');

    final flows = listFlows(root);

    expect(flows.map((f) => f.title), ['A', 'B']);
  });

  group('buildFlowFile', () {
    String build(String steps) => buildFlowFile(
      title: 'Covered filter',
      precondition: 'Dashboard',
      app: 'com.example.app',
      inlineSteps: steps,
    );

    test('writes a header and the steps as typed, without describe steps', () {
      final file = build('''
- describe: true
- tap: { id: button_filter }
# confirm
- tap: { id: sheet_button_primary_action }
''');

      expect(file, startsWith('# Covered filter\n# Precondition: Dashboard\n'));
      expect(file, isNot(contains('describe')));
      expect(file, contains('  # confirm'));
    });

    test('rewrites a one-line flow list one step per line, without describe', () {
      final file = build(
        '[{tap: {id: a}}, {describe: true}, {waitFor: {text: "User ID: TEST12", timeout: 3}}, '
        '{type: "72"}, {tap: {id: "icons/x.png", optional: true}}]',
      );

      expect(
        file,
        contains(
          '  - tap: { id: a }\n'
          '  - waitFor: { text: "User ID: TEST12", timeout: 3 }\n'
          '  - type: "72"\n'
          '  - tap: { id: icons/x.png, optional: true }\n',
        ),
      );
      expect(file, isNot(contains('describe')));
    });

    test('a rewritten flow list loads back to the same steps', () {
      const steps = '[{tap: {anyOf: [{id: a}, {id: b}]}}, {assert: {id: f, value: "TEST12"}}]';
      final flow = loadYaml(build(steps)) as YamlMap;
      final loaded = flow['steps'] as YamlList;

      expect(((loaded[0] as YamlMap)['tap'] as YamlMap)['anyOf'], hasLength(2));
      expect(((loaded[1] as YamlMap)['assert'] as YamlMap)['value'], 'TEST12');
    });

    test('produces a flow the runner can load', () {
      final flow = loadYaml(build('- tap: { id: a }\n- waitFor: { text: "B" }')) as YamlMap;

      expect(flow['app'], 'com.example.app');
      expect(flow['steps'], hasLength(2));
    });
  });
}
