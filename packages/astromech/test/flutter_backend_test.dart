import 'dart:io';

import 'package:astromech/src/flutter_backend.dart';
import 'package:test/test.dart';

void main() {
  test('probeDriverIsolate gives up on a VM service that accepts but never answers', () async {
    // A suspended app: the WebSocket handshake succeeds, getVM never gets a reply.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.transform(WebSocketTransformer()).listen(sockets.add);
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    final watch = Stopwatch()..start();
    final isolate = await FlutterBackend.probeDriverIsolate(
      'http://127.0.0.1:${server.port}/token=/',
      const Duration(milliseconds: 300),
    );

    expect(isolate, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('probeDriverIsolate returns null when nothing listens', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    expect(
      await FlutterBackend.probeDriverIsolate(
        'http://127.0.0.1:$port/',
        const Duration(seconds: 1),
      ),
      isNull,
    );
  });
}
