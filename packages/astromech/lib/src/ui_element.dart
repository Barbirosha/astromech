import 'dart:convert';

/// One node of the accessibility tree returned by `mobilecli dump ui`.
class UiElement {
  const UiElement({
    required this.ref,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.identifier,
    this.label,
    this.text,
    this.value,
    this.isFocused = false,
  });

  factory UiElement.fromJson(Map<String, dynamic> json) {
    final rect = json['rect'] as Map<String, dynamic>? ?? const {};
    return UiElement(
      ref: json['ref'] as String? ?? '',
      type: json['type'] as String? ?? '',
      identifier: json['identifier'] as String?,
      label: json['label'] as String?,
      text: json['text'] as String?,
      value: json['value'] as String?,
      isFocused: json['focused'] as bool? ?? false,
      x: (rect['x'] as num? ?? 0).toDouble(),
      y: (rect['y'] as num? ?? 0).toDouble(),
      width: (rect['width'] as num? ?? 0).toDouble(),
      height: (rect['height'] as num? ?? 0).toDouble(),
    );
  }

  final String ref;
  final String type;
  final String? identifier;
  final String? label;
  final String? text;
  final String? value;
  final bool isFocused;
  final double x;
  final double y;
  final double width;
  final double height;

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  @override
  String toString() {
    final parts = [
      ref,
      type,
      if (identifier != null) 'id=$identifier',
      if (text != null) 'text="$text"',
      if (value != null) 'value="$value"',
      'at=${x.round()},${y.round()} size=${width.round()}x${height.round()}',
    ];
    return parts.join(' ');
  }
}

/// Parses the JSON printed by `mobilecli dump ui`.
List<UiElement> parseUiDump(String output) {
  final json = jsonDecode(output) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>? ?? const {};
  final elements = data['elements'] as List<dynamic>? ?? const [];
  return elements.map((e) => UiElement.fromJson(e as Map<String, dynamic>)).toList();
}
