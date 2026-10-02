import 'package:astromech/src/ui_element.dart';

/// What a flow step points at: exactly one of [id], [text] or [label],
/// or `anyOf: [...]` when a screen shows one of several elements depending on its state.
class Selector {
  const Selector({this.id, this.text, this.label, this.anyOf = const []});

  factory Selector.fromMap(Map<dynamic, dynamic> map) {
    final alternatives = map['anyOf'];
    if (alternatives is List) {
      if (alternatives.isEmpty) throw FormatException('anyOf needs at least one selector: $map');
      return Selector(
        anyOf: [for (final item in alternatives) Selector.fromMap(item as Map<dynamic, dynamic>)],
      );
    }

    final selector = Selector(
      id: map['id'] as String?,
      text: map['text'] as String?,
      label: map['label'] as String?,
    );
    final count = [selector.id, selector.text, selector.label].whereType<String>().length;
    if (count != 1) {
      throw FormatException('Selector needs exactly one of id / text / label, got: $map');
    }
    return selector;
  }

  final String? id;
  final String? text;
  final String? label;
  final List<Selector> anyOf;

  bool matches(UiElement element) {
    if (anyOf.isNotEmpty) return anyOf.any((selector) => selector.matches(element));
    if (id != null) return element.identifier == id;
    if (text != null) return element.text == text || element.label == text;
    return element.label == label;
  }

  @override
  String toString() {
    if (anyOf.isNotEmpty) return 'anyOf(${anyOf.join(' | ')})';
    if (id != null) return 'id=$id';
    if (text != null) return 'text="$text"';
    return 'label="$label"';
  }
}

class FindResult {
  const FindResult({required this.element, required this.otherMatches});

  /// The element to act on, or null when nothing visible matched.
  final UiElement? element;

  /// Visible matches outside [element] - anything here means the pick may be a guess.
  /// Nodes nested inside [element] (a card's icon and texts share its id) don't count.
  final List<UiElement> otherMatches;
}

/// Picks the element a [selector] refers to.
///
/// The dump lists the top route (and its overlays) before the routes beneath
/// it, and a route underneath can still sit partly on screen during or after
/// an iOS transition. So among the elements whose centre is on screen the
/// first one in dump order wins.
FindResult findElement(List<UiElement> elements, Selector selector) {
  if (elements.isEmpty) return const FindResult(element: null, otherMatches: []);

  final screen = _screenBounds(elements);
  final visible = elements
      .where(selector.matches)
      .where((e) => e.width > 0 && e.height > 0)
      .where((e) => _isOnScreen(e, screen))
      .toList();

  if (visible.isEmpty) return const FindResult(element: null, otherMatches: []);

  final picked = visible.first;
  return FindResult(
    element: picked,
    otherMatches: visible.skip(1).where((e) => !_contains(picked, e)).toList(),
  );
}

bool _contains(UiElement outer, UiElement inner) {
  return inner.centerX >= outer.x &&
      inner.centerX <= outer.x + outer.width &&
      inner.centerY >= outer.y &&
      inner.centerY <= outer.y + outer.height;
}

({double width, double height}) _screenBounds(List<UiElement> elements) {
  // The first node is the full-screen root.
  final root = elements.first;
  return (width: root.x + root.width, height: root.y + root.height);
}

bool _isOnScreen(UiElement element, ({double width, double height}) screen) {
  return element.centerX >= 0 &&
      element.centerY >= 0 &&
      element.centerX <= screen.width &&
      element.centerY <= screen.height;
}
