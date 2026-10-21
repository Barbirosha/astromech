import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A debug session an IDE registered with the Dart Tooling Daemon (DTD).
class DebugSession {
  const DebugSession({required this.id, required this.name, this.deviceId, this.vmServiceUri});

  final String id;
  final String name;
  final String? deviceId;
  final String? vmServiceUri;

  @override
  String toString() => '$name ($id)';
}

/// The DTD address from a process list: the IDE starts DevTools with
/// `--dtd-uri ws://127.0.0.1:<port>/<token>`.
String? dtdUriFrom(String processList) {
  return RegExp(r'--dtd-uri[= ](ws://\S+)').firstMatch(processList)?.group(1);
}

/// The DTD the running IDE (VS Code with the Dart extension) started, if any.
Future<String?> findDtdUri() async {
  final result = await Process.run('ps', ['-axo', 'command']);
  if (result.exitCode != 0) return null;
  return dtdUriFrom(result.stdout as String);
}

/// Sessions in an `Editor.getDebugSessions` result.
List<DebugSession> parseDebugSessions(Map<String, dynamic> result) {
  final sessions = result['debugSessions'] as List<dynamic>? ?? const [];
  return [
    for (final session in sessions.cast<Map<String, dynamic>>())
      DebugSession(
        id: session['id'] as String,
        name: session['name'] as String? ?? '',
        deviceId: session['flutterDeviceId'] as String?,
        vmServiceUri: session['vmServiceUri'] as String?,
      ),
  ];
}

/// The session running the app astromech is connected to. Sessions on another
/// device are skipped; when several remain, [isOurApp] tells them apart (the
/// IDE reports the DDS address, not the VM service address mDNS advertises,
/// so addresses can't simply be compared).
Future<DebugSession?> pickSession(
  List<DebugSession> sessions, {
  required String device,
  required Future<bool> Function(DebugSession session) isOurApp,
}) async {
  final onDevice = sessions.where((s) => s.deviceId == null || s.deviceId == device).toList();
  if (onDevice.length == 1) return onDevice.single;
  for (final session in onDevice) {
    if (await isOurApp(session)) return session;
  }
  return null;
}

/// An error the DTD or the IDE behind it returned for a call.
class DtdException implements Exception {
  DtdException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal JSON-RPC client for the editor service the Dart IDE extension
/// registers with DTD (`Editor.getDebugSessions`, `Editor.hotReload`, ...).
class DtdClient {
  DtdClient._(this._socket) {
    _socket.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
  }

  final WebSocket _socket;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;

  static Future<DtdClient> connect(String uri) async {
    return DtdClient._(await WebSocket.connect(uri).timeout(const Duration(seconds: 5)));
  }

  Future<List<DebugSession>> getDebugSessions() async {
    return parseDebugSessions(await call('Editor.getDebugSessions'));
  }

  Future<void> hotReload(String sessionId) =>
      call('Editor.hotReload', {'debugSessionId': sessionId});

  Future<void> hotRestart(String sessionId) =>
      call('Editor.hotRestart', {'debugSessionId': sessionId});

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) {
    final id = ++_nextId;
    final reply = _pending[id] = Completer<Map<String, dynamic>>();
    _socket.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return reply.future.timeout(timeout, onTimeout: () => throw DtdException('$method timed out'));
  }

  Future<void> close() => _socket.close();

  void _onMessage(Object? data) {
    if (data is! String) return;
    final message = jsonDecode(data) as Map<String, dynamic>;
    final reply = _pending.remove(message['id']);
    if (reply == null) return;
    final error = message['error'] as Map<String, dynamic>?;
    if (error != null) {
      reply.completeError(DtdException('${error['message'] ?? error}'));
    } else {
      reply.complete(message['result'] as Map<String, dynamic>? ?? const {});
    }
  }

  void _onDone() {
    for (final reply in _pending.values) {
      reply.completeError(DtdException('DTD connection closed'));
    }
    _pending.clear();
  }
}
