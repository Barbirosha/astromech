import 'package:astromech/src/element_finder.dart';
import 'package:astromech/src/mobilecli.dart';
import 'package:astromech/src/ui_backend.dart';
import 'package:astromech/src/ui_element.dart';

/// Reads the OS accessibility tree through `mobilecli dump ui` and taps by coordinates.
/// Works with any app and build, but each dump takes seconds.
class NativeBackend implements UiBackend {
  NativeBackend(this._cli);

  final MobileCli _cli;
  List<UiElement> _lastDump = const [];

  @override
  Duration get pollInterval => const Duration(milliseconds: 300);

  @override
  Future<UiMatch?> find(Selector selector) async {
    _lastDump = await _cli.dumpUi();
    final result = findElement(_lastDump, selector);
    final element = result.element;
    if (element == null) return null;

    return UiMatch(
      description: '$element',
      handle: element,
      text: element.text,
      value: element.value,
      label: element.label,
      otherMatches: [for (final other in result.otherMatches) '$other'],
    );
  }

  @override
  Future<void> tap(UiMatch match) {
    final element = match.handle as UiElement;
    return _cli.tap(element.centerX, element.centerY);
  }

  @override
  Future<void> typeText(String text) => _cli.typeText(text);

  @override
  Future<List<String>> describeScreen() async {
    return [
      for (final element in _lastDump.where((e) => e.identifier != null).take(30)) '$element',
    ];
  }

  @override
  Future<void> close() async {}
}
