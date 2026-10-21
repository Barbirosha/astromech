import 'package:astromech/src/step_validation.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

List<String> validate(String flowList) => validateSteps(loadYaml(flowList));

void main() {
  group('validateSteps', () {
    test('accepts every documented step form', () {
      const steps = '''
[{tap: {id: a}}, {tap: {text: "T", optional: true, timeout: 1}}, {tap: {anyOf: [{id: a}, {id: b}]}},
 {waitFor: {id: a}}, {waitGone: {text: "T", timeout: 2}}, {assert: {id: f, value: "V"}},
 {assert: {id: f, text: "T"}}, {type: "72"}, {screenshot: s.png}, {describe: true}, {button: HOME},
 {goHome: true}, {reload: true}, {restart: true}]''';

      expect(validate(steps), isEmpty);
    });

    test('rejects an unknown step', () {
      expect(validate('[{type: abc}, {swipe: down}]').single, contains('unknown step "swipe"'));
    });

    test('rejects a step with two keys', () {
      expect(validate('[{tap: {id: a}, timeout: 3}]').single, contains('exactly one key'));
    });

    test('rejects an assert without an id', () {
      expect(validate('[{assert: {text: "T"}}]').single, contains('assert needs id'));
    });

    test('rejects unknown keys inside a step', () {
      expect(validate('[{tap: {id: a, offset: 3}}]').single, contains('unknown keys [offset]'));
    });

    test('rejects a selector with two targets', () {
      expect(validate('[{tap: {id: a, text: b}}]').single, contains('exactly one of id / text'));
    });

    test('rejects a map where a plain value is expected', () {
      expect(validate('[{type: {text: a}}]').single, contains('plain value'));
    });
  });
}
