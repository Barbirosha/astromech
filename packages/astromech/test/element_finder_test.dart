import 'dart:io';

import 'package:astromech/src/element_finder.dart';
import 'package:astromech/src/ui_element.dart';
import 'package:test/test.dart';

void main() {
  // Real dump: Manual Approval on top, Dashboard and Review routes still in the
  // tree underneath, shifted left by the iOS push transition.
  final elements = parseUiDump(
    File('test/fixtures/manual_approval_over_dashboard.json').readAsStringSync(),
  );

  group('findElement', () {
    test('finds an element by id', () {
      final result = findElement(elements, const Selector(id: 'manual_approval_user_id_input'));

      expect(result.element?.ref, '@e6');
      expect(result.otherMatches, isEmpty);
    });

    test('prefers the top route when the same id is on several routes', () {
      final result = findElement(elements, const Selector(id: 'header_action_right'));

      expect(result.element?.ref, '@e10');
      expect(result.otherMatches.map((e) => e.ref), ['@e34', '@e47']);
    });

    test('skips a node whose centre is off screen', () {
      final result = findElement(elements, const Selector(id: 'dashboard_header_bottom_link'));

      // @e15 is at x=-117, its centre stays left of the screen.
      expect(result.element?.ref, '@e16');
      expect(result.otherMatches, isEmpty);
    });

    test('does not count nodes nested inside the picked one as other matches', () {
      const root = UiElement(ref: '@e1', type: 'Box', x: 0, y: 0, width: 400, height: 800);
      const card = UiElement(
        ref: '@e2',
        type: 'Text',
        identifier: 'card',
        x: 10,
        y: 10,
        width: 300,
        height: 60,
      );
      const icon = UiElement(
        ref: '@e3',
        type: 'Image',
        identifier: 'card',
        x: 20,
        y: 20,
        width: 20,
        height: 20,
      );

      final result = findElement([root, card, icon], const Selector(id: 'card'));

      expect(result.element?.ref, '@e2');
      expect(result.otherMatches, isEmpty);
    });

    test('returns no element when nothing matches', () {
      final result = findElement(elements, const Selector(id: 'missing'));

      expect(result.element, isNull);
    });

    test('matches text against both text and label', () {
      const element = UiElement(
        ref: '@e2',
        type: 'Button',
        label: 'Continue',
        x: 0,
        y: 0,
        width: 10,
        height: 10,
      );

      final result = findElement([element], const Selector(text: 'Continue'));

      expect(result.element?.ref, '@e2');
    });
  });

  group('Selector.fromMap', () {
    test('anyOf matches any of its selectors', () {
      final selector = Selector.fromMap({
        'anyOf': [
          {'id': 'missing'},
          {'id': 'manual_approval_button_continue'},
        ],
      });

      expect(findElement(elements, selector).element?.ref, '@e7');
    });

    test('rejects an empty anyOf', () {
      expect(() => Selector.fromMap({'anyOf': <Object>[]}), throwsFormatException);
    });

    test('rejects a map without a selector key', () {
      expect(() => Selector.fromMap({'timeout': 5}), throwsFormatException);
    });

    test('rejects a map with two selector keys', () {
      expect(() => Selector.fromMap({'id': 'a', 'text': 'b'}), throwsFormatException);
    });
  });
}
