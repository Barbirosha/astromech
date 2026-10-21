import 'dart:convert';
import 'dart:io';

import 'package:astromech/src/agent_prompt.dart';

const hintsFile = 'astromech/HINTS.md';

/// `astromech check "<task>"` - runs the check agent as a separate headless
/// Claude Code process on Haiku with thinking OFF: a subagent started from a
/// session inherits that session's thinking and is about twice as slow.
Future<int> checkCommand(List<String> args) async {
  var model = 'haiku';
  final taskWords = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--model' && i + 1 < args.length) {
      model = args[++i];
    } else {
      taskWords.add(args[i]);
    }
  }
  if (taskWords.isEmpty) {
    stderr.writeln('Usage: astromech check [--model haiku] "<what to check>"');
    return 64;
  }

  final process = await Process.start(
    'claude',
    [
      '-p',
      '--model',
      model,
      '--settings',
      '{"alwaysThinkingEnabled":false}',
      '--system-prompt',
      systemPrompt(hints: _readHints()),
      '--tools',
      'Bash',
      'Grep',
      'Glob',
      'Read',
      '--allowedTools',
      'Bash(astromech *)',
      'Grep',
      'Glob',
      'Read',
      '--permission-mode',
      'dontAsk',
      '--disable-slash-commands',
      '--strict-mcp-config',
      '--output-format',
      'json',
      taskWords.join(' '),
    ],
    environment: {'MAX_THINKING_TOKENS': '0'},
  );
  // No stdin: `claude -p` otherwise waits for it.
  await process.stdin.close();
  final output = await process.stdout.transform(utf8.decoder).join();
  final errors = await process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;

  final Map<String, dynamic> result;
  try {
    result = jsonDecode(output) as Map<String, dynamic>;
  } on FormatException {
    stderr.writeln('claude failed (exit $code):\n$errors$output');
    return code == 0 ? 1 : code;
  }

  stdout
    ..writeln((result['result'] as String? ?? '').trim())
    ..writeln()
    ..writeln(_summary(result));
  return result['is_error'] == true ? 1 : 0;
}

/// The agent prompt, followed by the project's hints when it has any.
String systemPrompt({String? hints}) {
  if (hints == null || hints.trim().isEmpty) return agentPrompt;
  return '$agentPrompt\n## Project hints ($hintsFile)\n\n${hints.trim()}\n';
}

String? _readHints() {
  final file = File(hintsFile);
  return file.existsSync() ? file.readAsStringSync() : null;
}

String _summary(Map<String, dynamic> result) {
  final seconds = (result['duration_ms'] as num? ?? 0) / 1000;
  final modelSeconds = (result['duration_api_ms'] as num? ?? 0) / 1000;
  final cost = result['total_cost_usd'] as num? ?? 0;
  return 'time ${seconds.toStringAsFixed(1)}s (model ${modelSeconds.toStringAsFixed(1)}s), '
      '${result['num_turns']} turns, \$${cost.toStringAsFixed(3)}';
}
