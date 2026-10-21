// Runs a device flow (YAML) against a simulator / emulator, tapping elements
// by their Flutter semantics id instead of coordinates.
//
// Usage:
//   astromech run <flow.yaml>
//   astromech run --inline '<yaml steps>'
//
// Nothing project-specific has to be passed: the device is the one booted
// simulator, the app is the one running debug build with registerAstromech()
// (found via mDNS), the pid file is build/astromech/flutter_run.pid. --device / --app /
// --vm-service / --pid-file override them when several are running.
//
// --inline runs steps given on the command line instead of a file - for driving
// the app one step at a time, e.g.:
//   --inline '- describe: true'
//   --inline '- tap: { id: button_filter }' --describe-after
// --describe-after prints what is on screen once the steps pass, saving a
// separate `describe` call after every action.
// --timeout <s> sets the default step timeout (10 s otherwise).
// Steps are validated before anything runs - a typo fails without touching the device.
//
// Flow library (astromech/flows):
//   astromech run --list
//       every saved flow with what it checks (its first comment line) and its precondition
//   ... --inline '<yaml steps>' --save-as <flow.yaml> --title "<what it checks>"
//       [--precondition "<start screen>"] [--overwrite]
//       once the inline steps pass, saves them as a flow (describe steps dropped);
//       the run must start and end on the app's first screen (use goHome)
//
// Backends:
//   flutter (default) talks to astromech_driver inside a debug build over the VM
//           service - only the top route, ids under MergeSemantics too, milliseconds per
//           lookup. Screenshots via `xcrun simctl`.
//   native  reads the OS accessibility tree via mobilecli - any build, ~4 s per lookup.
//   Hardware buttons and launch / terminate go through mobilecli.
//
// Flow format:
//   device: <id>                 # optional, else --device or $MOBILECLI_DEVICE
//   app: com.parcelscloud.apps.snow   # optional, used by `launch: true`
//   timeout: 10                  # optional, seconds per step (default 10)
//   steps:
//     - launch: true             # or a bundle id
//     - tap: { id: some_id }     # selector: exactly one of id / text / label
//     - tap: { anyOf: [ { id: a }, { id: b } ] }   # whichever the screen shows
//     - tap: { id: intro_ok, optional: true, timeout: 2 }   # skipped if it never shows up
//     - type: abc12x             # into the focused field
//     - waitFor: { text: "User ID: ABC12X", timeout: 5 }
//     - waitGone: { id: some_button }   # the screen holding it was closed
//     - assert: { id: some_input, value: ABC12X }   # or text: / label:
//     - button: HOME
//     - screenshot: name.png
//     - describe: true           # print what is on screen (ids, texts, values)
//     - goHome: true             # close screens / sheets / dialogs back to the first screen
//     - reload: true             # hot reload (SIGUSR1 to `flutter run --pid-file build/astromech/flutter_run.pid`)
//     - restart: true            # hot restart (SIGUSR2); --pid-file <path> to use another pid file
//
// Every step that points at an element polls the UI until the element shows
// up (or the step times out), so no sleeps are needed between steps.
// With the native backend routes underneath stay in the UI tree (partly on
// screen after an iOS push), so wait for ids unique to the target screen, or
// use waitGone to confirm a screen was closed.
// On failure a screenshot is saved and the process exits with code 1.

import 'dart:io';

import 'package:astromech/src/dtd_client.dart';
import 'package:astromech/src/element_finder.dart';
import 'package:astromech/src/flow_library.dart';
import 'package:astromech/src/flutter_backend.dart';
import 'package:astromech/src/mobilecli.dart';
import 'package:astromech/src/native_backend.dart';
import 'package:astromech/src/simulator.dart';
import 'package:astromech/src/step_validation.dart';
import 'package:astromech/src/ui_backend.dart';
import 'package:yaml/yaml.dart';

const _defaultTimeout = Duration(seconds: 10);
const _defaultPidFile = 'build/astromech/flutter_run.pid';
const _flowsRoot = 'astromech/flows';
const _usage =
    'Usage: astromech run <flow.yaml> | --inline <yaml steps> | --list\n'
    '  [--app <bundle id>] [--device <id>] [--out <dir>] [--backend flutter|native]\n'
    '  [--vm-service <uri>] [--pid-file <path>] [--describe-after] [--timeout <s>]\n'
    '  [--save-as <flow.yaml> --title <what it checks> [--precondition <start>] [--overwrite]]';

/// `astromech run` - runs a flow file or `--inline` steps against the app.
Future<void> runCommand(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    stderr.writeln(_usage);
    exit(64);
  }

  if (options.list) {
    listFlows(Directory(_flowsRoot)).forEach(stdout.writeln);
    exit(0);
  }

  final saveAs = options.saveAs;
  if (saveAs != null && File(saveAs).existsSync() && !options.overwrite) {
    stderr.writeln('$saveAs already exists - pass --overwrite to replace it.');
    exit(64);
  }

  final YamlMap flow;
  try {
    flow = _loadFlow(options);
  } on YamlException catch (error) {
    stderr.writeln('Invalid YAML in the steps: ${error.message}\n$stepForms');
    exit(65);
  }
  final steps = (flow['steps'] as YamlList?) ?? YamlList();
  final problems = validateSteps(steps);
  if (problems.isNotEmpty) {
    stderr.writeln('${problems.join('\n')}\n$stepForms');
    exit(65);
  }
  final String device;
  try {
    device =
        options.device ??
        flow['device'] as String? ??
        Platform.environment['MOBILECLI_DEVICE'] ??
        await bootedSimulator();
  } on DeviceNotFoundException catch (error) {
    stderr.writeln(error.message);
    exit(69);
  }

  final flowPath = options.flowPath;
  final flowName = flowPath == null ? 'inline' : flowPath.split('/').last.replaceAll('.yaml', '');
  final outDir = Directory(options.outDir ?? 'build/astromech/$flowName')
    ..createSync(recursive: true);
  final cli = MobileCli(device: device);
  final UiBackend backend;
  try {
    backend = options.backend == 'flutter'
        ? await FlutterBackend.connect(
            uri: options.vmService,
            bundleId: options.app ?? flow['app'] as String?,
          )
        : NativeBackend(cli);
  } on AppNotReachableException catch (error) {
    stderr.writeln(error.message);
    exit(69);
  }
  final app =
      options.app ?? flow['app'] as String? ?? (backend is FlutterBackend ? backend.appName : null);
  stdout.writeln(
    'Backend: ${options.backend}${app == null ? '' : ' | app: $app'} | device: $device',
  );

  final runner = _FlowRunner(
    cli: cli,
    device: device,
    backend: backend,
    app: app,
    describeAfter: options.describeAfter,
    pidFile: options.pidFile ?? _defaultPidFile,
    defaultTimeout:
        _secondsOrNull(options.timeout) ?? _secondsOrNull(flow['timeout']) ?? _defaultTimeout,
    outDir: outDir,
  );

  // A saved flow must be re-runnable: it starts and ends on the app's first screen.
  final checksHome = saveAs != null && backend is FlutterBackend;
  if (checksHome && !await backend.isHome()) {
    stdout.writeln('FAIL not on the first screen - run {goHome: true} first.');
    await backend.close();
    exit(1);
  }

  var ok = await runner.run(steps.cast<YamlMap>());
  if (ok && checksHome && !await backend.isHome()) {
    stdout.writeln('Not saved: the flow must end on the first screen - add {goHome: true}.');
    ok = false;
  }
  await backend.close();

  final inline = options.inline;
  if (ok && saveAs != null && inline != null) {
    File(saveAs)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        buildFlowFile(
          title: options.title ?? '',
          precondition: options.precondition ?? 'the app is open on the start screen, logged in.',
          app: app,
          inlineSteps: inline,
        ),
      );
    stdout.writeln('Saved as $saveAs');
  }
  exit(ok ? 0 : 1);
}

Duration? _secondsOrNull(Object? seconds) {
  if (seconds is! num) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// A flow file, or `--inline` steps wrapped into a flow.
YamlMap _loadFlow(_Options options) {
  final inline = options.inline;
  if (inline != null) return loadYaml('steps:\n${_indent(inline)}') as YamlMap;
  return loadYaml(File(options.flowPath ?? '').readAsStringSync()) as YamlMap;
}

String _indent(String yaml) => yaml.split('\n').map((line) => '  $line').join('\n');

typedef _Options = ({
  bool list,
  String? saveAs,
  String? title,
  String? precondition,
  bool overwrite,
  String? flowPath,
  String? inline,
  String? app,
  String? device,
  String? outDir,
  String backend,
  String? vmService,
  bool describeAfter,
  num? timeout,
  String? pidFile,
});

_Options? _parseArgs(List<String> args) {
  var list = false;
  String? saveAs;
  String? title;
  String? precondition;
  var overwrite = false;
  String? flowPath;
  String? inline;
  String? app;
  String? device;
  String? outDir;
  var backend = 'flutter';
  String? vmService;
  var describeAfter = false;
  num? timeout;
  String? pidFile;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final hasValue = i + 1 < args.length;
    if (arg == '--list') {
      list = true;
    } else if (arg == '--save-as' && hasValue) {
      saveAs = args[++i];
    } else if (arg == '--title' && hasValue) {
      title = args[++i];
    } else if (arg == '--precondition' && hasValue) {
      precondition = args[++i];
    } else if (arg == '--overwrite') {
      overwrite = true;
    } else if (arg == '--device' && hasValue) {
      device = args[++i];
    } else if (arg == '--out' && hasValue) {
      outDir = args[++i];
    } else if (arg == '--inline' && hasValue) {
      inline = args[++i];
    } else if (arg == '--app' && hasValue) {
      app = args[++i];
    } else if (arg == '--backend' && hasValue) {
      backend = args[++i];
      if (backend != 'native' && backend != 'flutter') return null;
    } else if (arg == '--vm-service' && hasValue) {
      vmService = args[++i];
    } else if (arg == '--describe-after') {
      describeAfter = true;
    } else if (arg == '--timeout' && hasValue) {
      timeout = num.tryParse(args[++i]);
      if (timeout == null || timeout <= 0) return null;
    } else if (arg == '--pid-file' && hasValue) {
      pidFile = args[++i];
    } else if (!arg.startsWith('--')) {
      flowPath = arg;
    } else {
      return null;
    }
  }
  if (list) {
    if (flowPath != null || inline != null) return null;
  } else if ((flowPath == null) == (inline == null)) {
    return null;
  }
  // A flow is only saved from --inline steps, and needs to say what it checks.
  if (saveAs != null && (inline == null || title == null)) return null;
  return (
    list: list,
    saveAs: saveAs,
    title: title,
    precondition: precondition,
    overwrite: overwrite,
    flowPath: flowPath,
    inline: inline,
    app: app,
    device: device,
    outDir: outDir,
    backend: backend,
    vmService: vmService,
    describeAfter: describeAfter,
    timeout: timeout,
    pidFile: pidFile,
  );
}

class _StepFailure implements Exception {
  _StepFailure(this.message);

  final String message;
}

class _FlowRunner {
  _FlowRunner({
    required this.cli,
    required this.device,
    required this.backend,
    required this.app,
    required this.describeAfter,
    required this.pidFile,
    required this.defaultTimeout,
    required this.outDir,
  });

  final MobileCli cli;
  final String device;
  final UiBackend backend;
  final String? app;
  final bool describeAfter;
  final String pidFile;

  /// `flutter run` writes its output here when started the way the device-check skill says.
  String get logFile => pidFile.replaceAll(RegExp(r'\.pid$'), '.log');
  final Duration defaultTimeout;
  final Directory outDir;

  Future<bool> run(List<YamlMap> steps) async {
    final total = Stopwatch()..start();
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final title = '${i + 1}/${steps.length} ${_describe(step)}';
      final watch = Stopwatch()..start();
      try {
        final note = await _runStep(step);
        stdout.writeln('OK   $title (${_seconds(watch)})${note == null ? '' : ' - $note'}');
      } on Object catch (error) {
        final message = error is _StepFailure ? error.message : '$error';
        stdout.writeln('FAIL $title (${_seconds(watch)})\n     $message');
        await _dumpFailureContext();
        stdout.writeln('Flow failed after ${_seconds(total)}.');
        return false;
      }
    }
    stdout.writeln('Flow passed in ${_seconds(total)}.');
    if (describeAfter) await _printScreen();
    return true;
  }

  /// Runs one step; returns an optional note for the report.
  Future<String?> _runStep(YamlMap step) async {
    if (step.length != 1) {
      throw _StepFailure('a step must have exactly one key (tap, waitFor, ...), got: $step');
    }
    final key = step.keys.single as String;
    final arg = step[key];

    switch (key) {
      case 'launch':
        final bundleId = arg is String ? arg : app;
        if (bundleId == null) throw _StepFailure('launch: no bundle id and no `app:` in the flow');
        await cli.launchApp(bundleId);
        return null;
      case 'terminate':
        final bundleId = arg is String ? arg : app;
        if (bundleId == null) {
          throw _StepFailure('terminate: no bundle id and no `app:` in the flow');
        }
        await cli.terminateApp(bundleId);
        return null;
      case 'tap':
        final args = arg as YamlMap;
        final match = await _tap(Selector.fromMap(args), _timeoutOf(args));
        if (match == null) return _notFound(args);
        return _ambiguityNote(match);
      case 'type':
        await backend.typeText('$arg');
        return null;
      case 'waitFor':
        final args = arg as YamlMap;
        final match = await _waitFor(Selector.fromMap(args), _timeoutOf(args));
        // Several matches are fine here (e.g. a status repeated down a list) - only taps can miss.
        if (match == null) return _notFound(args);
        return null;
      case 'waitGone':
        final args = arg as YamlMap;
        await _waitGone(Selector.fromMap(args), _timeoutOf(args));
        return null;
      case 'assert':
        return _assert(arg as YamlMap);
      case 'button':
        await cli.pressButton('$arg');
        return null;
      case 'goHome':
        final flutter = backend;
        if (flutter is! FlutterBackend) throw _StepFailure('goHome needs --backend flutter');
        final popped = await flutter.goHome();
        return popped == 0 ? 'already home' : 'closed $popped';
      case 'reload':
      case 'restart':
        return _reload(restart: key == 'restart');
      case 'describe':
        final lines = await backend.describeScreen();
        return lines.isEmpty ? 'nothing with an id or text' : '\n       ${lines.join('\n       ')}';
      case 'screenshot':
        final path = '${outDir.path}/$arg';
        await _screenshot(path);
        return path;
      default:
        throw _StepFailure('unknown step "$key"');
    }
  }

  /// `assert: { id: x, value: Y }` - waits until the element's value / text / label equals Y.
  Future<String?> _assert(YamlMap args) async {
    final id = args['id'];
    if (id is! String) {
      throw _StepFailure('assert needs id: (use waitFor to check a text on screen)');
    }
    final selector = Selector(id: id);
    final expected = <String, String>{
      for (final key in ['value', 'text', 'label'])
        if (args.containsKey(key)) key: '${args[key]}',
    };
    if (expected.isEmpty) throw _StepFailure('assert needs value: / text: / label: to compare');

    final timeout = _timeoutOf(args);
    final watch = Stopwatch()..start();
    while (true) {
      final match = await backend.find(selector);
      final mismatches = match == null ? const <String>[] : _mismatches(match, expected);
      if (match != null && mismatches.isEmpty) return null;
      if (watch.elapsed >= timeout) {
        throw _StepFailure(match == null ? 'not found' : mismatches.join(', '));
      }
      await Future<void>.delayed(backend.pollInterval);
    }
  }

  List<String> _mismatches(UiMatch match, Map<String, String> expected) {
    final actual = {'value': match.value, 'text': match.text, 'label': match.label};
    return [
      for (final MapEntry(:key, :value) in expected.entries)
        if (actual[key] != value) '$key expected "$value" but was "${actual[key]}"',
    ];
  }

  /// Finds and taps [selector], retrying until [timeout] when the tap itself
  /// fails - the target can be found and then move or get covered mid-transition.
  /// Null when it never became tappable.
  Future<UiMatch?> _tap(Selector selector, Duration timeout) async {
    final watch = Stopwatch()..start();
    while (true) {
      final match = await backend.find(selector);
      if (match != null) {
        try {
          await backend.tap(match);
          return match;
        } on Object {
          // Moved or covered between find and tap - look again.
        }
      }
      if (watch.elapsed >= timeout) return null;
      await Future<void>.delayed(backend.pollInterval);
    }
  }

  Future<UiMatch?> _waitFor(Selector selector, Duration timeout) async {
    final watch = Stopwatch()..start();
    while (true) {
      final match = await backend.find(selector);
      if (match != null || watch.elapsed >= timeout) return match;
      await Future<void>.delayed(backend.pollInterval);
    }
  }

  Future<void> _waitGone(Selector selector, Duration timeout) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (await backend.find(selector) == null) return;
      if (watch.elapsed >= timeout) throw _StepFailure('still on screen');
      await Future<void>.delayed(backend.pollInterval);
    }
  }

  Duration _timeoutOf(YamlMap args) {
    final seconds = args['timeout'];
    if (seconds is! num) return defaultTimeout;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Hot reload / restart, whichever way the app was started:
  /// - `flutter run --pid-file <pidFile>` in a terminal -> SIGUSR1 / SIGUSR2,
  ///   the same as pressing r / R there;
  /// - F5 in VS Code -> the Dart extension's `Editor.hotReload` / `Editor.hotRestart`
  ///   through the Dart Tooling Daemon, the same as its reload button.
  Future<String?> _reload({required bool restart}) async {
    final flutter = backend;
    if (flutter is! FlutterBackend) throw _StepFailure('reload / restart need --backend flutter');

    final pid = _livePid();
    final note = pid != null
        ? await _reloadViaSignal(flutter, pid, restart: restart)
        : await _reloadViaIde(flutter, restart: restart);
    // Let the reassembled frame settle before the next step reads the screen.
    await Future<void>.delayed(backend.pollInterval * 3);
    return note;
  }

  /// The pid in [pidFile] when that process is still running.
  int? _livePid() {
    final file = File(pidFile);
    final pid = file.existsSync() ? int.tryParse(file.readAsStringSync().trim()) : null;
    if (pid == null) return null;
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0 ? pid : null;
  }

  Future<String?> _reloadViaSignal(FlutterBackend flutter, int pid, {required bool restart}) async {
    final done = await flutter.reloadWith(
      () async => Process.killPid(pid, restart ? ProcessSignal.sigusr2 : ProcessSignal.sigusr1),
      restart: restart,
      timeout: const Duration(seconds: 15),
    );
    if (!done) {
      throw _StepFailure(
        restart
            ? 'restart did not happen in 15 s - a compile error? See the flutter run output'
            : 'nothing was reloaded in 15 s - no code changed since the last reload '
                  '(flutter run says "Reloaded 0 libraries"), or a compile error in the flutter run output',
      );
    }
    return 'via flutter run (pid $pid)';
  }

  Future<String?> _reloadViaIde(FlutterBackend flutter, {required bool restart}) async {
    final dtdUri = await findDtdUri();
    if (dtdUri == null) {
      throw _StepFailure(
        'no way to reload: no running `flutter run --pid-file $pidFile`, and no IDE debug '
        'session (start the app with F5 in VS Code with the Dart extension)',
      );
    }

    final client = await DtdClient.connect(dtdUri);
    try {
      final sessions = await client.getDebugSessions();
      final session = await pickSession(
        sessions,
        device: device,
        isOurApp: (s) async {
          final uri = s.vmServiceUri;
          return uri != null && await FlutterBackend.driverIsolateAt(uri) == flutter.isolateId;
        },
      );
      if (session == null) {
        throw _StepFailure(
          'no IDE debug session runs this app on $device'
          '${sessions.isEmpty ? '' : ' - sessions: ${sessions.join(', ')}'}',
        );
      }

      if (restart) {
        final done = await flutter.reloadWith(
          () => client.hotRestart(session.id),
          restart: true,
          timeout: const Duration(seconds: 30),
        );
        if (!done) throw _StepFailure('restart did not happen in 30 s - see the IDE debug console');
      } else {
        // The IDE answers once the reload is done, also when nothing changed.
        await client.hotReload(session.id);
      }
      return 'via ${session.name}';
    } on DtdException catch (error) {
      throw _StepFailure('${restart ? 'restart' : 'reload'} via the IDE failed: $error');
    } finally {
      await client.close();
    }
  }

  /// `optional: true` steps (e.g. a one-off intro modal) are skipped when nothing shows up.
  String _notFound(YamlMap args) {
    if (args['optional'] == true) return 'skipped, not shown';
    throw _StepFailure('not found');
  }

  /// Simulator screenshots without mobilecli for the flutter backend.
  Future<void> _screenshot(String path) {
    if (backend is FlutterBackend) return simulatorScreenshot(device, path);
    return cli.screenshot(path);
  }

  Future<void> _printScreen() async {
    // Let a tap's navigation / animation settle before reading the new screen.
    await Future<void>.delayed(backend.pollInterval * 3);
    stdout.writeln('Screen:');
    for (final line in await backend.describeScreen()) {
      stdout.writeln('  $line');
    }
  }

  String? _ambiguityNote(UiMatch match) {
    if (match.otherMatches.isEmpty) return null;
    return 'WARNING used ${match.description}, also matched: ${match.otherMatches.join('; ')}';
  }

  Future<void> _dumpFailureContext() async {
    final path = '${outDir.path}/failure.png';
    try {
      await _screenshot(path);
      stdout.writeln('     screenshot: $path');
    } on Object catch (error) {
      stdout.writeln('     screenshot failed: $error');
    }

    final List<String> onScreen;
    try {
      onScreen = await backend.describeScreen();
    } on Object catch (error) {
      stdout.writeln('     describing the screen failed: $error');
      return;
    }
    if (onScreen.isEmpty) return;
    stdout.writeln('     on screen:');
    for (final line in onScreen) {
      stdout.writeln('       $line');
    }
  }

  String _describe(YamlMap step) {
    if (step.length != 1) return 'invalid step $step';
    final key = step.keys.single;
    final arg = step[key];
    if (arg is YamlMap) {
      final parts = [for (final MapEntry(:key, :value) in arg.entries) '$key=$value'];
      return '$key ${parts.join(' ')}';
    }
    return '$key $arg';
  }

  String _seconds(Stopwatch watch) => '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
}
