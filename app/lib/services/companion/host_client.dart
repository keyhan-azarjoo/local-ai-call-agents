import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'host_server.dart' show companionPort, discoveryHello, discoveryPort;

class FoundHost {
  FoundHost(this.name, this.address, this.port);
  final String name, address;
  final int port;
  String get base => 'http://$address:$port';
}

class HostError implements Exception {
  HostError(this.message, {this.unpaired = false});
  final String message;
  final bool unpaired;
  @override
  String toString() => message;
}

/// A phone's (or second computer's) connection to the main LocalAILine computer.
class HostClient {
  HostClient(this.base, this.token, {http.Client? client}) : _c = client ?? http.Client();
  final String base, token;
  final http.Client _c;

  /// Looks for LocalAILine computers on the local network (UDP broadcast).
  static Future<List<FoundHost>> discover({Duration wait = const Duration(seconds: 2)}) async {
    final found = <String, FoundHost>{};
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..broadcastEnabled = true;
      s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = s!.receive();
        if (d == null) return;
        try {
          final j = jsonDecode(utf8.decode(d.data)) as Map;
          if (j['app'] == 'LocalAILine') found[d.address.address] = FoundHost('${j['name']}', d.address.address, (j['port'] as num).toInt());
        } catch (_) {}
      });
      for (var i = 0; i < 3; i++) {
        s.send(utf8.encode(discoveryHello), InternetAddress('255.255.255.255'), discoveryPort);
        await Future.delayed(wait ~/ 3);
      }
    } catch (_) {
      // Some phones block broadcast; typing the address still works.
    } finally {
      s?.close();
    }
    return found.values.toList();
  }

  /// Turns "192.168.1.20" or "mac-mini.local:7420" into a base URL.
  static String normalize(String input) {
    var a = input.trim();
    if (a.isEmpty) return a;
    if (!a.startsWith('http')) a = 'http://$a';
    final u = Uri.parse(a);
    return '${u.scheme}://${u.host}:${u.hasPort ? u.port : companionPort}';
  }

  static Future<String> hello(String base) async {
    try {
      final r = await http.get(Uri.parse('$base/api/hello')).timeout(const Duration(seconds: 5));
      final j = jsonDecode(r.body) as Map;
      if (j['app'] != 'LocalAILine') throw HostError('That address is not a LocalAILine computer.');
      return '${j['name']}';
    } on HostError {
      rethrow;
    } catch (_) {
      throw HostError('Can’t reach that computer. Check it’s on, LocalAILine is open, and you’re on the same network.');
    }
  }

  /// Exchanges the 6-digit code for this device's own key.
  static Future<({String token, String hostName})> pair(String base, String code, String deviceName, String platform) async {
    final r = await http
        .post(Uri.parse('$base/api/pair'), body: jsonEncode({'code': code, 'name': deviceName, 'platform': platform}))
        .timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map;
    if (r.statusCode != 200) throw HostError('${j['error'] ?? 'Pairing failed.'}');
    return (token: j['token'] as String, hostName: j['hostName'] as String);
  }

  Future<dynamic> get(String route) async {
    final r = await _c.get(Uri.parse('$base/api/$route'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Future<dynamic> post(String route, Map<String, Object?> body, {Duration timeout = const Duration(minutes: 3)}) async {
    final r = await _c
        .post(Uri.parse('$base/api/$route'), headers: {'Authorization': 'Bearer $token'}, body: jsonEncode(body))
        .timeout(timeout);
    return _parse(r);
  }

  dynamic _parse(http.Response r) {
    final j = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode == 401) throw HostError('This device was removed on the computer. Pair it again.', unpaired: true);
    if (r.statusCode != 200) throw HostError('${(j is Map ? j['error'] : null) ?? 'Error ${r.statusCode}'}');
    return j;
  }

  // ---------------- live events ----------------

  WebSocket? _ws;
  Timer? _retry;
  bool _closed = false;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get connected => _ws != null;

  /// Replies to approval requests coming from the computer.
  Future<bool> Function(Map<String, dynamic> request)? onApprove;

  Future<void> connect() async {
    _closed = false;
    try {
      final ws = await WebSocket.connect('${base.replaceFirst('http', 'ws')}/api/events?token=$token').timeout(const Duration(seconds: 8));
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      _events.add({'type': 'connected'});
      ws.listen((raw) async {
        final m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
        if (m['type'] == 'approve') {
          final ok = await (onApprove?.call(m) ?? Future.value(false));
          ws.add(jsonEncode({'id': m['id'], 'ok': ok}));
          return;
        }
        _events.add(m);
      }, onDone: _lost, onError: (_) => _lost());
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _ws = null;
    _events.add({'type': 'disconnected'});
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), connect);
  }

  void answer(String callId, String action) => _ws?.add(jsonEncode({'type': 'answer', 'callId': callId, 'action': action}));

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _ws?.close();
    _ws = null;
  }
}
