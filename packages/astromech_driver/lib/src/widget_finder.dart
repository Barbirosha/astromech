import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// What to look for: exactly one of [id] (`Semantics.identifier`), [text] or [key] (`ValueKey<String>`).
class WidgetSelector {
  const WidgetSelector({this.id, this.text, this.key});

  factory WidgetSelector.fromParams(Map<String, String> params) {
    final selector = WidgetSelector(id: params['id'], text: params['text'], key: params['key']);
    final count = [selector.id, selector.text, selector.key].whereType<String>().length;
    if (count != 1) {
      throw ArgumentError('Pass exactly one of id / text / key, got: $params');
    }
    return selector;
  }

  final String? id;
  final String? text;
  final String? key;

  bool matches(Widget widget) {
    if (id != null) return widget is Semantics && widget.properties.identifier == id;
    if (key != null) {
      final widgetKey = widget.key;
      return widgetKey is ValueKey<String> && widgetKey.value == key;
    }
    return _textOf(widget) == text;
  }

  @override
  String toString() {
    if (id != null) return 'id=$id';
    if (key != null) return 'key=$key';
    return 'text="$text"';
  }
}

class FoundWidget {
  const FoundWidget({required this.element, required this.box});

  final Element element;
  final RenderBox box;

  Rect get rect => box.localToGlobal(Offset.zero) & box.size;

  /// The text of the first `Text` inside, e.g. a button's label.
  String? get text {
    String? found;
    void visit(Element element) {
      if (found != null) return;
      found = _textOf(element.widget);
      element.visitChildElements(visit);
    }

    visit(element);
    return found;
  }

  /// The current value of a text field inside, if any.
  String? get value {
    String? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is EditableText) {
        found = widget.controller.text;
        return;
      }
      element.visitChildElements(visit);
    }

    visit(element);
    return found;
  }

  Map<String, Object?> toJson() {
    final rect = this.rect;
    return {
      'widget': element.widget.runtimeType.toString(),
      'text': text,
      'value': value,
      'rect': {'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height},
    };
  }
}

/// Finds widgets the user can actually see and tap.
///
/// A widget counts as visible when a hit test at its centre lands on it, on
/// something inside it, or on one of its own ancestors (e.g. the card behind
/// a non-interactive label). Anything covering it - a route pushed on top, a
/// modal barrier, a bottom sheet - lands on an unrelated render object
/// instead, so routes underneath are skipped without guessing.
class WidgetFinder {
  const WidgetFinder(this._binding);

  final WidgetsBinding _binding;

  List<FoundWidget> findVisible(WidgetSelector selector) {
    final found = <FoundWidget>[];
    final seenBoxes = <RenderBox>{};

    void visit(Element element) {
      if (selector.matches(element.widget)) {
        final box = _boxOf(element);
        // Text builds a RichText with the same text - keep one hit per box.
        if (box != null && seenBoxes.add(box) && _isVisible(box)) {
          found.add(FoundWidget(element: element, box: box));
        }
      }
      element.visitChildElements(visit);
    }

    final root = _binding.rootElement;
    if (root != null) visit(root);
    return found;
  }

  /// Everything visible with an id or a text - for failure reports and for an
  /// agent deciding its next step, so kept short:
  /// - a text already shown as the text of the id'd widget around it is skipped;
  /// - an id that is just an image path (`icons/close.png`) with no text is skipped.
  List<Map<String, Object?>> describeScreen({int limit = 80}) {
    final described = <Map<String, Object?>>[];
    final seenBoxes = <RenderBox>{};

    void visit(Element element, String? enclosingIdText) {
      if (described.length >= limit) return;
      final widget = element.widget;
      final id = widget is Semantics ? widget.properties.identifier : null;
      final ownText = _textOf(widget);
      var childContext = enclosingIdText;

      final isDuplicateText = id == null && ownText != null && ownText == enclosingIdText;
      final isImageId = id != null && _imagePath.hasMatch(id);
      if ((id != null || ownText != null) && !isDuplicateText) {
        final box = _boxOf(element);
        if (box != null && seenBoxes.add(box) && _isVisible(box)) {
          final found = FoundWidget(element: element, box: box);
          final json = {'id': ?id, ...found.toJson()};
          if (!(isImageId && json['text'] == null)) described.add(json);
          if (id != null) childContext = json['text'] as String?;
        }
      }
      element.visitChildElements((child) => visit(child, childContext));
    }

    final root = _binding.rootElement;
    if (root != null) visit(root, null);
    return described;
  }

  RenderBox? _boxOf(Element element) {
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) return null;
    if (renderObject.size.isEmpty) return null;
    return renderObject;
  }

  bool _isVisible(RenderBox box) {
    final view = _binding.platformDispatcher.implicitView;
    if (view == null) return false;

    final center = box.localToGlobal(box.size.center(Offset.zero));
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (!screen.contains(center)) return false;

    final result = HitTestResult();
    _binding.hitTestInView(result, center, view.viewId);
    // The path runs front to back; a RenderParagraph also adds its TextSpans,
    // which are not render objects, so take the front-most render object.
    final front = result.path.map((entry) => entry.target).whereType<RenderObject>().firstOrNull;
    if (front == null) return false;

    return _isSelfOrAncestor(box, of: front) || _isSelfOrAncestor(front, of: box);
  }

  /// Whether [candidate] is [of] or one of its render-tree ancestors.
  bool _isSelfOrAncestor(RenderObject candidate, {required RenderObject of}) {
    RenderObject? current = of;
    while (current != null) {
      if (identical(current, candidate)) return true;
      current = current.parent;
    }
    return false;
  }
}

final _imagePath = RegExp(r'\.(png|jpe?g|svg|webp|gif)$', caseSensitive: false);

String? _textOf(Widget widget) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  return null;
}
