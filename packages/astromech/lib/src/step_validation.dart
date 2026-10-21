import 'package:astromech/src/element_finder.dart';

/// What each step accepts - printed with validation errors so a model writing
/// steps sees the allowed forms instead of guessing.
const stepForms = '''
Allowed steps (each step map has exactly ONE key):
  {tap: {id: x}} | {tap: {text: "T"}} | {tap: {anyOf: [{id: a}, {id: b}]}}   + optional: true, timeout: s
  {waitFor: {id|text|anyOf...}} | {waitGone: {id|text|anyOf...}}           + optional: true, timeout: s
  {assert: {id: x, value: "V"}} | {assert: {id: x, text: "T"}}              + timeout: s
  {type: "text"} | {screenshot: name.png} | {describe: true} | {button: HOME}
  {goHome: true}   (closes screens / sheets / dialogs back to the first screen)
  {reload: true} | {restart: true}   (hot reload / restart via flutter run --pid-file)
  {launch: true} | {terminate: true}''';

const _selectorSteps = {'tap', 'waitFor', 'waitGone'};
const _selectorStepKeys = {'id', 'text', 'label', 'anyOf', 'timeout', 'optional'};
const _assertKeys = {'id', 'value', 'text', 'label', 'timeout'};
const _scalarSteps = {'type', 'screenshot', 'button'};
const Set<String> _knownSteps = {
  ..._selectorSteps,
  ..._scalarSteps,
  'assert',
  'describe',
  'launch',
  'terminate',
  'reload',
  'restart',
  'goHome',
};

/// Problems in [steps], one message per bad step - empty when every step is runnable.
/// Run before touching the device, so a typo costs nothing instead of a timeout.
List<String> validateSteps(Object? steps) {
  if (steps is! List) return ['steps must be a list, got: $steps'];

  return [
    for (var i = 0; i < steps.length; i++)
      if (_validateStep(steps[i]) case final error?) 'step ${i + 1} ${steps[i]}: $error',
  ];
}

String? _validateStep(Object? step) {
  if (step is! Map) return 'a step must be a map like {tap: {id: x}}';
  if (step.length != 1) return 'a step must have exactly one key, got ${step.keys.toList()}';

  final key = step.keys.single;
  final arg = step[key];
  if (!_knownSteps.contains(key)) return 'unknown step "$key"';

  if (_selectorSteps.contains(key)) {
    if (arg is! Map) return '$key needs a selector map like {$key: {id: x}}';
    final unknown = arg.keys.where((k) => !_selectorStepKeys.contains(k)).toList();
    if (unknown.isNotEmpty) return 'unknown keys $unknown in $key';
    return _selectorError(arg);
  }

  if (key == 'assert') {
    if (arg is! Map) return 'assert needs {assert: {id: x, value: "V"}}';
    final unknown = arg.keys.where((k) => !_assertKeys.contains(k)).toList();
    if (unknown.isNotEmpty) return 'unknown keys $unknown in assert';
    if (arg['id'] is! String) return 'assert needs id: (use waitFor to check a text on screen)';
    if (!arg.containsKey('value') && !arg.containsKey('text') && !arg.containsKey('label')) {
      return 'assert needs value: / text: / label: to compare';
    }
    return null;
  }

  if (_scalarSteps.contains(key) && (arg == null || arg is Map || arg is List)) {
    return '$key takes a plain value, like {$key: abc}';
  }
  return null;
}

String? _selectorError(Map<dynamic, dynamic> arg) {
  try {
    Selector.fromMap(arg);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}
