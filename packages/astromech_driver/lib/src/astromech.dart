import 'dart:convert';
import 'dart:developer';

import 'package:astromech_driver/src/home_navigator.dart';
import 'package:astromech_driver/src/widget_finder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Registers `ext.astromech.*` VM service extensions used by the `astromech` CLI.
///
/// Debug builds only: the call is a no-op elsewhere and, `kDebugMode` being
/// a compile-time constant, the rest is tree-shaken out of release builds.
///
/// - `ext.асф.find`      `id` | `text` | `key` -> the first visible match and how many others
/// - `ext.astromech.tap`       `id` | `text` | `key` -> waits until the match stops moving, then taps its centre
/// - `ext.astromech.enterText` `text`              -> types into the focused field through its formatters
/// - `ext.astromech.describe`                      -> visible widgets with an id or a text
/// - `ext.astromech.goHome`                        -> pops screens / sheets / dialogs back to the first screen
/// - `ext.astromech.isHome`                        -> whether nothing is left to pop
void registerAstromech() {
  if (!kDebugMode) return;

  final driver = _Driver(WidgetsBinding.instance);
  registerExtension('ext.astromech.find', (_, params) => _respond(() => driver.find(params)));
  registerExtension('ext.astromech.tap', (_, params) => _respond(() => driver.tap(params)));
  registerExtension(
    'ext.astromech.enterText',
    (_, params) => _respond(() => driver.enterText(params)),
  );
  registerExtension('ext.astromech.describe', (_, params) => _respond(driver.describe));
  registerExtension('ext.astromech.goHome', (_, params) => _respond(driver.goHome));
  registerExtension('ext.astromech.isHome', (_, params) => _respond(driver.isHome));
}

Future<ServiceExtensionResponse> _respond(Future<Map<String, Object?>> Function() handler) async {
  try {
    return ServiceExtensionResponse.result(jsonEncode(await handler()));
  } on Object catch (error) {
    return ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, '$error');
  }
}

class _Driver {
  _Driver(this._binding) : _finder = WidgetFinder(_binding), _home = HomeNavigator(_binding);

  static const _maxStabilityFrames = 60;

  final WidgetsBinding _binding;
  final WidgetFinder _finder;
  final HomeNavigator _home;
  final _clock = Stopwatch()..start();
  int _nextPointer = 1 << 20;

  Future<Map<String, Object?>> find(Map<String, String> params) async {
    final matches = _finder.findVisible(WidgetSelector.fromParams(params));
    if (matches.isEmpty) return {'found': false};

    return {
      'found': true,
      ...matches.first.toJson(),
      'otherMatches': matches.skip(1).map((m) => m.toJson()).toList(),
    };
  }

  Future<Map<String, Object?>> tap(Map<String, String> params) async {
    final selector = WidgetSelector.fromParams(params);
    final rect = await _waitUntilStill(selector);
    if (rect == null) throw StateError('$selector is not visible');

    _tapAt(rect.center);
    await _binding.endOfFrame;
    return {'tapped': true, 'x': rect.center.dx, 'y': rect.center.dy};
  }

  Future<Map<String, Object?>> enterText(Map<String, String> params) async {
    final text = params['text'];
    if (text == null) throw ArgumentError('enterText needs text');

    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final editable = focusedContext?.findAncestorStateOfType<EditableTextState>();
    if (editable == null) throw StateError('No focused text field - tap it first');

    // One character at a time, the way the platform keyboard reports input,
    // so input formatters and onChanged see every keystroke.
    for (final character in text.characters) {
      final current = editable.textEditingValue;
      final selection = current.selection.isValid
          ? current.selection
          : TextSelection.collapsed(offset: current.text.length);
      editable.updateEditingValue(
        TextEditingValue(
          text: current.text.replaceRange(selection.start, selection.end, character),
          selection: TextSelection.collapsed(offset: selection.start + character.length),
        ),
      );
    }
    await _binding.endOfFrame;
    return {'value': editable.textEditingValue.text};
  }

  Future<Map<String, Object?>> goHome() async {
    final popped = await _home.goHome();
    return {'popped': popped, 'isHome': _home.isHome};
  }

  Future<Map<String, Object?>> isHome() async => {'isHome': _home.isHome};

  Future<Map<String, Object?>> describe() async => {'widgets': _finder.describeScreen()};

  /// The match's rect once it is the same on two frames in a row - so a tap
  /// never lands mid-transition. Null when it never becomes visible.
  Future<Rect?> _waitUntilStill(WidgetSelector selector) async {
    Rect? previous;
    for (var frame = 0; frame < _maxStabilityFrames; frame++) {
      final matches = _finder.findVisible(selector);
      final rect = matches.isEmpty ? null : matches.first.rect;
      if (rect != null && rect == previous) return rect;

      previous = rect;
      _binding.scheduleFrame();
      await _binding.endOfFrame;
    }
    return previous;
  }

  void _tapAt(Offset position) {
    final viewId = _binding.platformDispatcher.implicitView?.viewId ?? 0;
    final pointer = _nextPointer++;
    GestureBinding.instance
      ..handlePointerEvent(
        PointerDownEvent(
          timeStamp: _clock.elapsed,
          pointer: pointer,
          position: position,
          viewId: viewId,
        ),
      )
      ..handlePointerEvent(
        PointerUpEvent(
          timeStamp: _clock.elapsed,
          pointer: pointer,
          position: position,
          viewId: viewId,
        ),
      );
  }
}
