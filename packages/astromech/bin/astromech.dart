import 'dart:io';

import 'package:astromech/src/check_command.dart';
import 'package:astromech/src/init_command.dart';
import 'package:astromech/src/runner.dart';

const _version = '0.1.0';

const _help =
    '''
astromech $_version - drive a running Flutter debug app from scripts and AI agents.

Usage:
  astromech run <flow.yaml> [options]        run a saved flow
  astromech run --inline '<yaml steps>'      run steps given on the command line
  astromech list                             saved flows with what they check
  astromech check "<what to check>"          let a thinking-free Haiku agent check it
                                             (needs the `claude` CLI); saves a new flow
  astromech init                             set up astromech/ and the Claude Code skill
                                             in the current project

The app must be a debug build started with `flutter run` that calls
registerAstromech() (package astromech_driver). `astromech run --help` lists
the step forms and options.''';

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'help' : args.first;
  final rest = args.skip(1).toList();

  switch (command) {
    case 'run':
      await runCommand(rest);
    case 'list':
      await runCommand(['--list', ...rest]);
    case 'check':
      exit(await checkCommand(rest));
    case 'init':
      exit(await initCommand(rest));
    case '--version' || 'version':
      stdout.writeln(_version);
    case 'help' || '--help' || '-h':
      stdout.writeln(_help);
    default:
      stderr.writeln('Unknown command "$command".\n\n$_help');
      exit(64);
  }
}
