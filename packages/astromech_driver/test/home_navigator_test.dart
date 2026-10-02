import 'dart:async';

import 'package:astromech_driver/src/home_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  Future<HomeNavigator> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: page('Home')));
    return HomeNavigator(tester.binding);
  }

  Future<void> push(WidgetTester tester, String name) async {
    unawaited(navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => page(name))));
    await tester.pumpAndSettle();
  }

  testWidgets('is home on the first screen', (tester) async {
    final home = await pumpApp(tester);

    expect(home.isHome, isTrue);
    expect(await home.goHome(settle: tester.pumpAndSettle), 0);
  });

  testWidgets('pops pushed screens back to the first one', (tester) async {
    final home = await pumpApp(tester);
    await push(tester, 'Second');
    await push(tester, 'Third');

    expect(home.isHome, isFalse);
    expect(await home.goHome(settle: tester.pumpAndSettle), 2);
    expect(home.isHome, isTrue);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('closes a bottom sheet and the screen under it', (tester) async {
    final home = await pumpApp(tester);
    await push(tester, 'Second');
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.text('Second')),
        builder: (_) => const Text('Sheet'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await home.goHome(settle: tester.pumpAndSettle), 2);
    expect(find.text('Sheet'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('closes a dialog on the root navigator above a nested navigator first', (
    tester,
  ) async {
    final nestedKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Navigator(
          key: nestedKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page('Tab root')),
        ),
      ),
    );
    final home = HomeNavigator(tester.binding);
    unawaited(
      nestedKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => page('Tab detail'))),
    );
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Tab detail')),
        builder: (_) => const AlertDialog(content: Text('Dialog')),
      ),
    );
    await tester.pumpAndSettle();

    expect(await home.goHome(settle: tester.pumpAndSettle), 2);
    expect(find.text('Dialog'), findsNothing);
    expect(find.text('Tab root'), findsOneWidget);
    expect(home.isHome, isTrue);
  });

  testWidgets('stops with an error when a screen refuses to close', (tester) async {
    final home = await pumpApp(tester);
    unawaited(
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => PopScope(canPop: false, child: page('Locked')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(home.goHome(settle: tester.pumpAndSettle), throwsStateError);
  });
}
