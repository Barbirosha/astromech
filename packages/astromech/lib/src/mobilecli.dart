import 'dart:io';

import 'package:astromech/src/ui_element.dart';

/// Thin wrapper over the `mobilecli` binary that mobile-mcp is built on.
class MobileCli {
  MobileCli({required this.device});

  final String device;
  String? _binary;

  /// `$MOBILECLI`, then `mobilecli` on PATH, then the copy npx installs for mobile-mcp.
  static Future<String> locate() async {
    final fromEnv = Platform.environment['MOBILECLI'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    final which = await Process.run('which', ['mobilecli']);
    if (which.exitCode == 0) return (which.stdout as String).trim();

    final home = Platform.environment['HOME'] ?? '';
    final npx = Directory('$home/.npm/_npx');
    if (npx.existsSync()) {
      for (final entry in npx.listSync()) {
        final candidate = File(
          '${entry.path}/node_modules/@mobilenext/mobilecli-darwin-arm64/mobilecli-darwin-arm64',
        );
        if (candidate.existsSync()) return candidate.path;
      }
    }

    throw StateError(
      'mobilecli not found. Set MOBILECLI, add it to PATH, or run mobile-mcp once via npx.',
    );
  }

  Future<List<UiElement>> dumpUi() async => parseUiDump(await _run(['dump', 'ui']));

  Future<void> tap(double x, double y) => _run(['io', 'tap', '${x.round()},${y.round()}']);

  Future<void> typeText(String text) => _run(['io', 'text', text]);

  Future<void> pressButton(String button) => _run(['io', 'button', button]);

  Future<void> launchApp(String bundleId) => _run(['apps', 'launch', bundleId]);

  Future<void> terminateApp(String bundleId) => _run(['apps', 'terminate', bundleId]);

  Future<void> screenshot(String path) => _run(['screenshot', '--output', path]);

  Future<String> _run(List<String> args) async {
    final binary = _binary ??= await locate();
    final result = await Process.run(binary, [...args, '--device', device]);
    if (result.exitCode != 0) {
      throw ProcessException(
        binary,
        args,
        '${result.stderr}${result.stdout}'.trim(),
        result.exitCode,
      );
    }
    return result.stdout as String;
  }
}
