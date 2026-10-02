import 'dart:io';

import 'package:astromech/src/skill_template.dart';

/// `astromech init` - sets up the current project; never overwrites existing files.
Future<int> initCommand(List<String> args) async {
  final created = <String>[];
  final kept = <String>[];

  void write(String path, String content) {
    final file = File(path);
    if (file.existsSync()) {
      kept.add(path);
      return;
    }
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    created.add(path);
  }

  write('astromech/flows/.gitkeep', '');
  write('astromech/HINTS.md', hintsTemplate);
  write('.claude/skills/astromech/SKILL.md', skillTemplate);

  final gitignore = File('.gitignore');
  final ignored = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
  const alreadyIgnoring = {'build/astromech/', 'build/', '/build/', '**/build/', 'build'};
  if (!ignored.split('\n').any((line) => alreadyIgnoring.contains(line.trim()))) {
    gitignore.writeAsStringSync(
      '${ignored.isEmpty || ignored.endsWith('\n') ? '' : '\n'}build/astromech/\n',
      mode: FileMode.append,
    );
    created.add('.gitignore: build/astromech/');
  }

  for (final path in created) {
    stdout.writeln('created  $path');
  }
  for (final path in kept) {
    stdout.writeln('kept     $path (already exists)');
  }
  stdout.writeln('''

Next:
  1. Add the driver (a regular dependency - it is a no-op in release; not on pub.dev yet):
       flutter pub add astromech_driver --git-url <astromech repo url> --git-path packages/astromech_driver --git-ref main
       or --path <path to astromech>/packages/astromech_driver
  2. In main(), after runApp(...):  registerAstromech();   // no-op outside debug builds
  3. flutter run ... --pid-file build/astromech/flutter_run.pid
  4. astromech run --inline '[{describe: true}]'
''');
  return 0;
}
