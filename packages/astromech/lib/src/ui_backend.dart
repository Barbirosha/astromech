import 'package:astromech/src/element_finder.dart';

/// An element a backend found on screen.
class UiMatch {
  const UiMatch({
    required this.description,
    required this.handle,
    this.text,
    this.value,
    this.label,
    this.otherMatches = const [],
  });

  final String description;

  /// Backend-specific reference used by [UiBackend.tap].
  final Object handle;

  final String? text;
  final String? value;
  final String? label;

  /// Other visible matches - non-empty means the pick may be a guess.
  final List<String> otherMatches;
}

/// How the runner sees and drives the app's UI.
///
/// Screenshots, hardware buttons and app launch stay on mobilecli whatever the
/// backend, since they live outside the app.
abstract interface class UiBackend {
  /// How long to wait between two polls of [find].
  Duration get pollInterval;

  Future<UiMatch?> find(Selector selector);

  Future<void> tap(UiMatch match);

  /// Types into the focused field.
  Future<void> typeText(String text);

  /// Lines describing what is on screen, for failure reports.
  Future<List<String>> describeScreen();

  Future<void> close();
}
