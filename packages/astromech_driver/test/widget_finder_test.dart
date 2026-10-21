import 'dart:async';

import 'package:astromech_driver/astromech_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WidgetFinder finder(WidgetTester tester) => WidgetFinder(tester.binding);

  Widget page(String id, {Widget? child}) => Scaffold(
    body: Column(
      children: [
        Semantics(identifier: id, child: const Text('Label')),
        ?child,
      ],
    ),
  );

  testWidgets('finds a widget by Semantics identifier', (tester) async {
    await tester.pumpWidget(MaterialApp(home: page('first')));

    final found = finder(tester).findVisible(const WidgetSelector(id: 'first'));

    expect(found, hasLength(1));
    expect(found.single.text, 'Label');
  });

  testWidgets('skips the route underneath a pushed one', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: page('first')));

    unawaited(
      navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => page('second'))),
    );
    await tester.pumpAndSettle();

    expect(finder(tester).findVisible(const WidgetSelector(id: 'first')), isEmpty);
    expect(finder(tester).findVisible(const WidgetSelector(id: 'second')), hasLength(1));
  });

  testWidgets('skips a widget covered by a dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(home: page('first')));

    final context = tester.element(find.text('Label'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Modal')),
      ),
    );
    await tester.pumpAndSettle();

    expect(finder(tester).findVisible(const WidgetSelector(id: 'first')), isEmpty);
    expect(finder(tester).findVisible(const WidgetSelector(text: 'Modal')), hasLength(1));
  });

  testWidgets('reports a Text once, not again for the RichText it builds', (tester) async {
    await tester.pumpWidget(MaterialApp(home: page('first')));

    expect(finder(tester).findVisible(const WidgetSelector(text: 'Label')), hasLength(1));
  });

  testWidgets('skips a widget scrolled off screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 2000),
              Semantics(identifier: 'far', child: const Text('Far')),
            ],
          ),
        ),
      ),
    );

    expect(finder(tester).findVisible(const WidgetSelector(id: 'far')), isEmpty);
  });

  testWidgets('finds an id under MergeSemantics, which hides it from the OS tree', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MergeSemantics(
            child: Semantics(
              identifier: 'checkbox_uncovered',
              child: Checkbox(value: false, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(
      finder(tester).findVisible(const WidgetSelector(id: 'checkbox_uncovered')),
      hasLength(1),
    );
  });

  testWidgets('reads the value of a text field inside the match', (tester) async {
    final controller = TextEditingController(text: 'ABC12X');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            identifier: 'input',
            child: TextField(controller: controller),
          ),
        ),
      ),
    );

    final found = finder(tester).findVisible(const WidgetSelector(id: 'input'));

    expect(found.single.value, 'ABC12X');
  });

  testWidgets('describeScreen skips texts repeated inside an id and image-path ids', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Semantics(identifier: 'button_filter', child: const Text('Filter')),
              Semantics(
                identifier: 'icons/close.png',
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: ColoredBox(color: Color(0x00000000)),
                ),
              ),
              const Text('Plain text'),
            ],
          ),
        ),
      ),
    );

    final described = WidgetFinder(tester.binding).describeScreen();

    expect(described.map((e) => e['id'] ?? e['text']), ['button_filter', 'Plain text']);
  });

  test('WidgetSelector.fromParams needs exactly one key', () {
    expect(() => WidgetSelector.fromParams({}), throwsArgumentError);
    expect(() => WidgetSelector.fromParams({'id': 'a', 'text': 'b'}), throwsArgumentError);
    expect(WidgetSelector.fromParams({'key': 'k'}).key, 'k');
  });
}
