import 'package:astromech_driver/astromech_driver.dart';
import 'package:astromech_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the filter checkboxes are findable by id despite MergeSemantics', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    final found = WidgetFinder(tester.binding).findVisible(const WidgetSelector(id: 'filter_done'));

    expect(found, hasLength(1));
  });
}
