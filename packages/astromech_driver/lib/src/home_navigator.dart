import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Brings the app back to its first screen the way the system back button
/// would - through `Navigator.maybePop` - so it needs no ids and works for
/// pushed screens, bottom sheets, dialogs and nested (e.g. go_router shell)
/// navigators alike.
class HomeNavigator {
  HomeNavigator(this._binding);

  static const _maxSettleFrames = 120;

  final WidgetsBinding _binding;

  /// Whether no navigator has anything left to pop.
  bool get isHome => _topPoppable() == null;

  /// Pops until [isHome], at most [maxPops] times. Returns how many routes were popped.
  ///
  /// [settle] waits for the pop animation to end - frames in production; tests
  /// pass `tester.pumpAndSettle`.
  Future<int> goHome({int maxPops = 10, Future<void> Function()? settle}) async {
    var popped = 0;
    while (popped < maxPops) {
      final navigator = _topPoppable();
      if (navigator == null) break;

      final before = _topRoute(navigator);
      await navigator.maybePop();
      await (settle ?? _waitForAnimations)();
      // maybePop reports "handled" even when a PopScope keeps the route, so
      // check that the top route actually changed.
      if (navigator.mounted && _topRoute(navigator) == before) {
        throw StateError('A screen refused to close (PopScope) after $popped pop(s)');
      }
      popped++;
    }
    return popped;
  }

  /// The innermost navigator the user would act on with "back": one that can
  /// pop and whose own route (for a nested navigator) is the visible one.
  NavigatorState? _topPoppable() {
    final navigators = <NavigatorState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        navigators.add(element.state as NavigatorState);
      }
      element.visitChildElements(visit);
    }

    final root = _binding.rootElement;
    if (root != null) visit(root);

    // Visited outer-first, so walk back from the innermost.
    for (final navigator in navigators.reversed) {
      if (!navigator.mounted || !navigator.canPop()) continue;
      // A nested navigator under a covered route (e.g. a dialog on the root
      // navigator above it) is not what "back" closes.
      final hostRoute = ModalRoute.of(navigator.context);
      if (hostRoute != null && !hostRoute.isCurrent) continue;
      return navigator;
    }
    return null;
  }

  /// The route on top of [navigator], read without changing anything:
  /// `popUntil` stops at the first route it visits when the predicate says so.
  Route<dynamic>? _topRoute(NavigatorState navigator) {
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  Future<void> _waitForAnimations() async {
    final scheduler = SchedulerBinding.instance;
    for (var frame = 0; frame < _maxSettleFrames; frame++) {
      await scheduler.endOfFrame;
      if (scheduler.transientCallbackCount == 0 && !scheduler.hasScheduledFrame) return;
    }
  }
}
