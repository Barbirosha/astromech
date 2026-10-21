import 'dart:io';

import 'package:yaml/yaml.dart';

/// A saved flow as shown by `--list`.
class FlowSummary {
  const FlowSummary({required this.path, required this.title, this.precondition, this.app});

  final String path;
  final String title;
  final String? precondition;
  final String? app;

  @override
  String toString() {
    final details = [
      if (app != null) 'app: $app',
      if (precondition != null) 'precondition: $precondition',
    ];
    return '$path\n  $title${details.isEmpty ? '' : '\n  ${details.join(' | ')}'}';
  }
}

/// Reads what a flow checks from its header comment: the comment lines before
/// `# Precondition:` are the title (joined), that line is the start state.
FlowSummary summarizeFlow(String path, String content) {
  final titleLines = <String>[];
  var titleDone = false;
  String? precondition;
  String? app;
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) {
      final comment = trimmed.substring(1).trim();
      if (comment.startsWith('Precondition:')) {
        precondition ??= comment.substring('Precondition:'.length).trim();
        titleDone = true;
      } else if (comment.isNotEmpty && !titleDone) {
        titleLines.add(comment);
      }
    } else if (titleLines.isNotEmpty) {
      // The first non-comment line after the title ends it.
      titleDone = true;
    }
    if (trimmed.startsWith('app:')) {
      app ??= trimmed.substring('app:'.length).trim();
    } else if (trimmed.startsWith('steps:')) {
      break;
    }
  }
  return FlowSummary(
    path: path,
    title: titleLines.isEmpty ? '(no description)' : titleLines.join(' '),
    precondition: precondition,
    app: app,
  );
}

/// Every `*.yaml` under [root], sorted by path.
List<FlowSummary> listFlows(Directory root) {
  if (!root.existsSync()) return const [];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [for (final file in files) summarizeFlow(file.path, file.readAsStringSync())];
}

/// The YAML file written by `--save-as` after an `--inline` run passed.
///
/// Block-style steps are kept as typed (comments and formatting included). A
/// one-line flow list (`[{tap: {id: a}}, ...]`, handy on a command line) is
/// rewritten one step per line. Either way `describe` steps are dropped - they
/// only helped while exploring.
String buildFlowFile({
  required String title,
  required String precondition,
  required String? app,
  required String inlineSteps,
}) {
  final trimmed = inlineSteps.trim();
  final steps = trimmed.startsWith('[') ? _flowListAsBlock(trimmed) : _blockSteps(inlineSteps);

  return [
    '# $title',
    '# Precondition: $precondition',
    '# No terminate/launch: a relaunch drops code applied by `flutter run` hot reload / restart.',
    if (app != null) 'app: $app',
    'steps:',
    steps,
    '',
  ].join('\n');
}

String _blockSteps(String inlineSteps) {
  return inlineSteps
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .where((line) => !RegExp(r'^\s*-\s*describe\s*:').hasMatch(line))
      .map((line) => '  $line')
      .join('\n');
}

String _flowListAsBlock(String flowList) {
  final steps = loadYaml(flowList) as YamlList;
  return [
    for (final step in steps.cast<YamlMap>())
      if (step.keys.first != 'describe') '  - ${_formatStep(step)}',
  ].join('\n');
}

String _formatStep(YamlMap step) => _formatMapEntries(step);

/// YAML flow style for one value: `{ k: v }`, `[a, b]` or a scalar.
String _formatValue(Object? value) {
  if (value is YamlMap) return '{ ${_formatMapEntries(value)} }';
  if (value is YamlList) return '[${value.map(_formatValue).join(', ')}]';
  return _scalar(value);
}

String _formatMapEntries(YamlMap map) {
  return [
    for (final MapEntry(:key, :value) in map.entries) '$key: ${_formatValue(value)}',
  ].join(', ');
}

final _needsQuotes = RegExp('[:{}\\[\\],#&*!|>\'"%@`]');
final _readsAsNonString = RegExp(
  r'^(true|false|yes|no|on|off|null|~|-?\d+(\.\d+)?)$',
  caseSensitive: false,
);

/// A scalar as YAML: plain when that reads back as the same string, quoted otherwise.
String _scalar(Object? value) {
  if (value is! String) return '$value';
  final plain =
      value.isNotEmpty &&
      value.trim() == value &&
      !_needsQuotes.hasMatch(value) &&
      !_readsAsNonString.hasMatch(value);
  if (plain) return value;
  return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
