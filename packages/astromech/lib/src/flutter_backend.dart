import 'dart:async';
import 'dart:io';

import 'package:astromech/src/element_finder.dart';
import 'package:astromech/src/ui_backend.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The app's VM service can't be found or no longer answers.
class AppNotReachableException implements Exception {
  AppNotReachableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the `ext.astromech.*` extensions registered by `astromech_driver`
/// in a debug build, over the same VM service `flutter run` uses.
///
/// Sees the widget tree directly: only the route on top, ids hidden from the OS
/// tree by MergeSemantics, and taps once the target has stopped moving.
class FlutterBackend implements UiBackend {
  FlutterBackend._(this._service, this._uri, this._isolateId, this.appName);

  static const _findExtension = 'ext.astromech.find';

  final VmService _service;
  final String _uri;
  String _isolateId;

  /// The bundle id the app advertises over mDNS, when it was discovered that way.
  final String? appName;

  /// Connects to [uri], or discovers the VM service of [bundleId] on the local
  /// network - or of the only running debug app with the driver when it is null.
  static Future<FlutterBackend> connect({required String? bundleId, String? uri}) async {
    final found = uri == null ? await _cachedOrDiscovered(bundleId) : (uri: uri, name: bundleId);
    final resolvedUri = found.uri;
    final service = await vmServiceConnectUri(_toWebSocket(resolvedUri));
    final isolateId = await _findDriverIsolate(service);
    if (isolateId == null) {
      await service.dispose();
      throw AppNotReachableException(
        'No isolate with $_findExtension at $resolvedUri - is the app a debug build that calls '
        'registerAstromech() (restart `flutter run` after adding it)?',
      );
    }
    return FlutterBackend._(service, resolvedUri, isolateId, found.name);
  }

  @override
  Duration get pollInterval => const Duration(milliseconds: 100);

  /// The app's isolate that runs the driver - the same id through any VM service proxy.
  String get isolateId => _isolateId;

  /// The isolate with the driver behind [uri] (e.g. an IDE's DDS address), or
  /// null when it can't be reached.
  static Future<String?> driverIsolateAt(String uri) async {
    try {
      final service = await vmServiceConnectUri(
        _toWebSocket(uri),
      ).timeout(const Duration(seconds: 3));
      try {
        return await _findDriverIsolate(service);
      } finally {
        await service.dispose();
      }
    } on Object {
      return null;
    }
  }

  @override
  Future<UiMatch?> find(Selector selector) async {
    for (final single in _flatten(selector)) {
      final response = await _call(_findExtension, _paramsOf(single));
      if (response['found'] != true) continue;

      final others = response['otherMatches'] as List<dynamic>? ?? const [];
      return UiMatch(
        description: '$single ${response['widget']} ${_rectOf(response)}',
        handle: single,
        text: response['text'] as String?,
        value: response['value'] as String?,
        otherMatches: [
          for (final other in others.cast<Map<String, dynamic>>())
            '${other['widget']} ${_rectOf(other)}',
        ],
      );
    }
    return null;
  }

  @override
  Future<void> tap(UiMatch match) =>
      _call('ext.astromech.tap', _paramsOf(match.handle as Selector));

  @override
  Future<void> typeText(String text) => _call('ext.astromech.enterText', {'text': text});

  @override
  Future<List<String>> describeScreen() async {
    final response = await _call('ext.astromech.describe', const {});
    final widgets = (response['widgets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final widget in widgets)
        [
          if (widget['id'] != null) 'id=${widget['id']}',
          if (widget['text'] != null) 'text="${widget['text']}"',
          if (widget['value'] != null) 'value="${widget['value']}"',
          _rectOf(widget),
        ].join(' '),
    ];
  }

  @override
  Future<void> close() => _service.dispose();

  /// Pops screens, sheets and dialogs back to the app's first screen. Returns how many were closed.
  Future<int> goHome() async {
    final response = await _call('ext.astromech.goHome', const {});
    return response['popped'] as int? ?? 0;
  }

  /// Whether the app is on its first screen with nothing left to pop.
  Future<bool> isHome() async => (await _call('ext.astromech.isHome', const {}))['isHome'] == true;

  /// Runs [trigger] (e.g. a signal to `flutter run`) and waits until the app
  /// has applied it: an `IsolateReload` event for a hot reload, a new isolate
  /// with the driver for a hot restart. Returns false on [timeout] - usually a
  /// compile error, which `flutter run` prints instead of reloading.
  Future<bool> reloadWith(
    Future<void> Function() trigger, {
    required bool restart,
    required Duration timeout,
  }) async {
    final previousIsolate = _isolateId;
    final reloaded = Completer<void>();
    final subscription = _service.onIsolateEvent.listen((event) {
      if (!restart && event.kind == EventKind.kIsolateReload) {
        if (!reloaded.isCompleted) reloaded.complete();
      }
    });
    await _service.streamListen(EventStreams.kIsolate);
    try {
      await trigger();
      if (!restart) {
        await reloaded.future.timeout(timeout);
        return true;
      }
      // A restart replaces the isolate - wait for the new one to register the driver.
      final watch = Stopwatch()..start();
      while (watch.elapsed < timeout) {
        final isolateId = await _findDriverIsolate(_service);
        if (isolateId != null && isolateId != previousIsolate) {
          _isolateId = isolateId;
          return true;
        }
        await Future<void>.delayed(pollInterval);
      }
      return false;
    } on TimeoutException {
      return false;
    } finally {
      await subscription.cancel();
      await _service.streamCancel(EventStreams.kIsolate);
    }
  }

  Future<Map<String, dynamic>> _call(String method, Map<String, String> params) async {
    try {
      return await _invoke(method, params);
    } on SentinelException {
      // Hot restart replaces the isolate - find the new one and retry once.
      final isolateId = await _findDriverIsolate(_service);
      if (isolateId == null) throw AppNotReachableException('App isolate at $_uri is gone');
      _isolateId = isolateId;
      return _invoke(method, params);
    }
  }

  Future<Map<String, dynamic>> _invoke(String method, Map<String, String> params) async {
    final response = await _service.callServiceExtension(
      method,
      isolateId: _isolateId,
      args: params,
    );
    return response.json ?? const {};
  }

  static Iterable<Selector> _flatten(Selector selector) {
    if (selector.anyOf.isEmpty) return [selector];
    return selector.anyOf.expand(_flatten);
  }

  static Map<String, String> _paramsOf(Selector selector) {
    final id = selector.id;
    if (id != null) return {'id': id};
    // Flutter has no separate accessibility label for plain widgets - match it as text.
    return {'text': selector.text ?? selector.label ?? ''};
  }

  static String _rectOf(Map<String, dynamic> json) {
    final rect = json['rect'] as Map<String, dynamic>?;
    if (rect == null) return '';
    num at(String key) => (rect[key] as num? ?? 0).round();
    return 'at=${at('x')},${at('y')} size=${at('width')}x${at('height')}';
  }

  static Future<String?> _findDriverIsolate(VmService service) async {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final id = ref.id;
      if (id == null) continue;
      final isolate = await service.getIsolate(id);
      if (isolate.extensionRPCs?.contains(_findExtension) ?? false) return id;
    }
    return null;
  }

  static String _toWebSocket(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == 'ws' || parsed.scheme == 'wss') return uri;
    final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
    return parsed.replace(scheme: 'ws', path: '${path}ws').toString();
  }

  /// The last URI found for [bundleId] if the app behind it still answers, else a fresh mDNS
  /// lookup - so step-by-step runs don't pay ~1.5 s of discovery each.
  static Future<({String uri, String? name})> _cachedOrDiscovered(String? bundleId) async {
    final cache = File('build/astromech/.vm_service_${bundleId ?? 'any'}');
    if (cache.existsSync()) {
      final [cachedUri, cachedName, ...] = '${cache.readAsStringSync()}\n'.split('\n');
      if (await _hasDriver(cachedUri.trim())) {
        return (uri: cachedUri.trim(), name: cachedName.trim().isEmpty ? null : cachedName.trim());
      }
    }

    final discovered = await _discover(bundleId);
    cache
      ..createSync(recursive: true)
      ..writeAsStringSync('${discovered.uri}\n${discovered.name}\n');
    return discovered;
  }

  /// Debug Flutter apps advertise their VM service over mDNS (`_dartVmService._tcp`)
  /// with the bundle id as instance name and the auth code in a TXT record.
  /// Stale records of earlier runs linger, so every candidate is probed.
  static Future<({String uri, String name})> _discover(String? bundleId) async {
    final browse = await _runFor(['-B', '_dartVmService._tcp', 'local.']);
    final names = {
      for (final line in browse.split('\n'))
        if (line.contains('_dartVmService._tcp.'))
          line
              .substring(line.indexOf('_dartVmService._tcp.') + '_dartVmService._tcp.'.length)
              .trim(),
    }.where((name) => bundleId == null || name == bundleId || name.startsWith('$bundleId ('));

    // Stale records of earlier runs linger - keep the ones that answer with the driver.
    final candidates = await Future.wait(
      names.map((name) async => (name: name, uri: await _resolve(name))),
    );
    final live = <({String uri, String name})>[];
    for (final candidate in candidates) {
      final uri = candidate.uri;
      if (uri != null && await _hasDriver(uri)) {
        // "com.app (2)" is mDNS de-duplicating names - the bundle id is before it.
        live.add((uri: uri, name: candidate.name.replaceFirst(RegExp(r' \(\d+\)$'), '')));
      }
    }

    if (live.length == 1) return live.single;
    if (live.isEmpty) {
      throw AppNotReachableException(
        'No running debug build${bundleId == null ? '' : ' of $bundleId'} with '
        'registerAstromech() found. Start it with `flutter run`, or pass --vm-service <uri>.',
      );
    }
    final apps = live.map((app) => app.name).toSet();
    if (apps.length == 1) return live.first;
    throw AppNotReachableException(
      'Several apps with the driver are running - pass --app: ${apps.join(', ')}',
    );
  }

  static Future<String?> _resolve(String instance) async {
    final output = await _runFor(['-L', instance, '_dartVmService._tcp', 'local.']);
    final port = RegExp(r'can be reached at \S+:(\d+)').firstMatch(output)?.group(1);
    final authCode = RegExp(r'authCode=(\S+)').firstMatch(output)?.group(1);
    if (port == null) return null;
    return 'http://127.0.0.1:$port/${authCode == null ? '' : '$authCode/'}';
  }

  static Future<bool> _hasDriver(String uri) async {
    try {
      final service = await vmServiceConnectUri(
        _toWebSocket(uri),
      ).timeout(const Duration(seconds: 2));
      try {
        return await _findDriverIsolate(service) != null;
      } finally {
        await service.dispose();
      }
    } on Object {
      return false;
    }
  }

  /// `dns-sd` never exits on its own - collect what it prints in a short window.
  static Future<String> _runFor(
    List<String> args, {
    Duration window = const Duration(milliseconds: 1500),
  }) async {
    final process = await Process.start('dns-sd', args);
    final output = StringBuffer();
    final subscription = process.stdout
        .transform(const SystemEncoding().decoder)
        .listen(output.write);
    await Future<void>.delayed(window);
    process.kill();
    await subscription.cancel();
    return output.toString();
  }
}
