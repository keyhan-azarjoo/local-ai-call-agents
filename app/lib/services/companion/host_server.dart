import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../data/db.dart';

/// Ports: HTTP/WebSocket for paired devices, and UDP for finding the computer.
const companionPort = 7420;
const discoveryPort = 7421;
const discoveryHello = 'LOCALAILINE_DISCOVER_V1';

Future<String> sha256Hex(String s) async =>
    (await Sha256().hash(utf8.encode(s))).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A paired device that is connected right now.
class LiveDevice {
  LiveDevice(this.id, this.name, this.socket);
  final int id;
  final String name;
  final WebSocket socket;
  final pending = <String, Completer<Map<String, dynamic>>>{};
  int _n = 0;

  void send(Map<String, Object?> m) => socket.add(jsonEncode(m));

  /// Sends a request and waits for the matching reply (approvals).
  Future<Map<String, dynamic>> ask(Map<String, Object?> m, Duration timeout) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_n++}';
    final c = Completer<Map<String, dynamic>>();
    pending[id] = c;
    send({...m, 'id': id});
    return c.future.timeout(timeout, onTimeout: () {
      pending.remove(id);
      return {'ok': false, 'timeout': true};
    });
  }
}

/// What a device chose when it rang.
class RingAnswer {
  RingAnswer(this.deviceId, this.deviceName, this.action);
  final int? deviceId;
  final String? deviceName;

  /// 'me' = answered on the device, 'ai' = let Ava answer, 'decline'.
  final String action;
}

typedef JsonHandler = Future<Object?> Function(int deviceId, Map<String, dynamic> body);

/// The computer's side of pairing. Runs only on the main (host) computer,
/// on the local network. No outside server is involved.
class HostServer {
  HostServer(this.db, {required this.hostName, required this.handlers});
  final Db db;
  final String hostName;

  /// API routes provided by the app, e.g. 'status', 'calls', 'chat', 'talk'.
  final Map<String, JsonHandler> handlers;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  final live = <int, LiveDevice>{};
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  String? pairingCode;
  DateTime? _codeExpires;
  int _badAttempts = 0;
  String? startError;
  int get port => _http?.port ?? companionPort;
  bool get running => _http != null;

  Future<void> start({int port = companionPort, bool discovery = true}) async {
    if (_http != null) return;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _http!.listen(_handle);
      startError = null;
    } catch (e) {
      startError = 'Could not open port $port: $e';
      return;
    }
    if (discovery) {
      try {
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
        _udp!.listen((ev) {
          if (ev != RawSocketEvent.read) return;
          final d = _udp!.receive();
          if (d == null || utf8.decode(d.data, allowMalformed: true) != discoveryHello) return;
          _udp!.send(utf8.encode(jsonEncode({'app': 'LocalAILine', 'name': hostName, 'port': this.port})), d.address, d.port);
        });
      } catch (_) {
        // Discovery is a convenience; typing the address still works.
      }
    }
  }

  Future<void> stop() async {
    for (final d in live.values) {
      await d.socket.close();
    }
    live.clear();
    await _http?.close(force: true);
    _http = null;
    _udp?.close();
    _udp = null;
  }

  /// A fresh 6-digit code, valid for 10 minutes.
  String newPairingCode() {
    pairingCode = (Random.secure().nextInt(900000) + 100000).toString();
    _codeExpires = DateTime.now().add(const Duration(minutes: 10));
    _badAttempts = 0;
    _changes.add(null);
    return pairingCode!;
  }

  /// IPv4 addresses phones can use to reach this computer.
  static Future<List<String>> localAddresses() async {
    final out = <String>[];
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.address.startsWith('169.254')) out.add(a.address);
      }
    }
    return out;
  }

  // ---------------- requests ----------------

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/api/hello') return _json(req, 200, {'app': 'LocalAILine', 'name': hostName, 'version': 1});
      if (path == '/api/pair' && req.method == 'POST') return _pair(req);

      final token = req.uri.queryParameters['token'] ?? req.headers.value('authorization')?.replaceFirst('Bearer ', '');
      final device = token == null ? null : await _deviceFor(token);
      if (device == null) return _json(req, 401, {'error': 'This device is not paired. Pair it again.'});

      if (path == '/api/events' && WebSocketTransformer.isUpgradeRequest(req)) return _events(req, device);

      final route = path.startsWith('/api/') ? path.substring(5) : '';
      final h = handlers[route];
      if (h == null) return _json(req, 404, {'error': 'Not found'});
      final raw = req.method == 'POST' ? await utf8.decodeStream(req) : '';
      final body = raw.isEmpty ? <String, dynamic>{} : (jsonDecode(raw) as Map).cast<String, dynamic>();
      return _json(req, 200, await h(device['id'] as int, body));
    } catch (e) {
      try {
        await _json(req, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  Future<Map<String, Object?>?> _deviceFor(String token) async {
    final rows = await db.all('devices', where: 'token_hash = ?', args: [await sha256Hex(token)]);
    if (rows.isEmpty) return null;
    await db.update('devices', rows.first['id'] as int, {'last_seen': DateTime.now().millisecondsSinceEpoch});
    return rows.first;
  }

  Future<void> _pair(HttpRequest req) async {
    final body = (jsonDecode(await utf8.decodeStream(req)) as Map).cast<String, dynamic>();
    final valid = pairingCode != null && _codeExpires != null && DateTime.now().isBefore(_codeExpires!);
    if (_badAttempts >= 5) {
      pairingCode = null;
      return _json(req, 429, {'error': 'Too many wrong codes. Show a new code on the computer.'});
    }
    if (!valid || body['code']?.toString().trim() != pairingCode) {
      _badAttempts++;
      return _json(req, 403, {'error': valid ? 'That code is not right.' : 'The code has expired. Show a new one on the computer.'});
    }
    final token = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    final id = await db.insert('devices', {
      'name': (body['name'] ?? 'Device').toString(),
      'platform': (body['platform'] ?? 'unknown').toString(),
      'token_hash': await sha256Hex(token),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'ring': 1,
    });
    await db.audit('System', 'Paired ${body['name']} (${body['platform']})');
    pairingCode = null; // one code, one device
    _changes.add(null);
    return _json(req, 200, {'token': token, 'deviceId': id, 'hostName': hostName});
  }

  Future<void> _events(HttpRequest req, Map<String, Object?> device) async {
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 20);
    final d = LiveDevice(device['id'] as int, device['name'] as String, ws);
    await live.remove(d.id)?.socket.close();
    live[d.id] = d;
    _changes.add(null);
    d.send({'type': 'hello', 'hostName': hostName});
    ws.listen((raw) {
      try {
        final m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
        final c = d.pending.remove(m['id']);
        if (c != null) {
          c.complete(m);
        } else if (m['type'] == 'answer') {
          _ringAnswer?.call(RingAnswer(d.id, d.name, m['action'] as String? ?? 'ai'), m['callId'] as String?);
        }
      } catch (_) {}
    }, onDone: () {
      if (live[d.id] == d) live.remove(d.id);
      _changes.add(null);
    });
  }

  Future<void> _json(HttpRequest req, int code, Object? body) async {
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  // ---------------- ringing ----------------

  void Function(RingAnswer, String?)? _ringAnswer;

  /// Rings every connected device that has "ring me" on. The first answer wins;
  /// with no answer within [timeout], Ava answers.
  Future<RingAnswer> ring({required String callId, required String from, required String number, required String line, Duration timeout = const Duration(seconds: 20)}) async {
    final targets = <LiveDevice>[];
    for (final d in live.values) {
      final rows = await db.all('devices', where: 'id = ?', args: [d.id]);
      if (rows.isNotEmpty && rows.first['ring'] == 1) targets.add(d);
    }
    if (targets.isEmpty) return RingAnswer(null, null, 'ai');
    final done = Completer<RingAnswer>();
    _ringAnswer = (a, id) {
      if (id == callId && !done.isCompleted) done.complete(a);
    };
    for (final d in targets) {
      d.send({'type': 'ring', 'callId': callId, 'from': from, 'number': number, 'line': line, 'seconds': timeout.inSeconds});
    }
    final answer = await done.future.timeout(timeout, onTimeout: () => RingAnswer(null, null, 'ai'));
    _ringAnswer = null;
    for (final d in targets) {
      d.send({'type': 'ring_end', 'callId': callId, 'answeredBy': answer.deviceName, 'action': answer.action});
    }
    return answer;
  }

  /// Asks a device to approve an action (tool use started from that device).
  Future<bool> approveOn(int deviceId, String server, String tool, Map<String, dynamic> args) async {
    final d = live[deviceId];
    if (d == null) return false;
    final r = await d.ask({'type': 'approve', 'server': server, 'tool': tool, 'args': args}, const Duration(seconds: 90));
    return r['ok'] == true;
  }

  void broadcast(Map<String, Object?> m) {
    for (final d in live.values) {
      d.send(m);
    }
  }
}
