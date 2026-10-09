import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:localailine_model/phone_lines.dart';

/// The phone gateway's control API (packages/localailine_sipgw): it signs in to people's phone
/// providers for their own numbers. It runs on this computer, on loopback, with a token made
/// for each start.
class SipGatewayClient {
  SipGatewayClient(this.base, this.token, {http.Client? client}) : _c = client ?? http.Client();

  /// e.g. http://127.0.0.1:53123
  final String base;
  final String token;
  final http.Client _c;

  static const _timeout = Duration(seconds: 10);

  Map<String, String> get _headers => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> _json(http.Response r) async {
    Map<String, dynamic> j;
    try {
      j = r.body.trim().isEmpty ? {} : (jsonDecode(r.body) as Map).cast<String, dynamic>();
    } catch (_) {
      j = {};
    }
    if (r.statusCode >= 300) throw SipGatewayError(r.statusCode, '${j['error'] ?? 'the phone gateway said ${r.statusCode}'}');
    return j;
  }

  /// Running and answering (no token needed).
  Future<bool> healthy() async {
    try {
      final r = await _c.get(Uri.parse('$base/healthz')).timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Adds or changes a line. Returns the line as the gateway now has it (with its status).
  Future<Map<String, dynamic>> put(String id, Map<String, Object> account) async =>
      _json(await _c.put(Uri.parse('$base/v1/accounts/${Uri.encodeComponent(id)}'), headers: _headers, body: jsonEncode(account)).timeout(_timeout));

  /// One line and its status, or null when the gateway doesn't have it.
  Future<Map<String, dynamic>?> get(String id) async {
    final r = await _c.get(Uri.parse('$base/v1/accounts/${Uri.encodeComponent(id)}'), headers: _headers).timeout(_timeout);
    if (r.statusCode == 404) return null;
    return _json(r);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final j = await _json(await _c.get(Uri.parse('$base/v1/accounts'), headers: _headers).timeout(_timeout));
    return [for (final a in (j['accounts'] as List? ?? const [])) (a as Map).cast<String, dynamic>()];
  }

  /// Signs the line out and removes it. False when there was no such line.
  Future<bool> delete(String id) async {
    final r = await _c.delete(Uri.parse('$base/v1/accounts/${Uri.encodeComponent(id)}'), headers: _headers).timeout(_timeout);
    if (r.statusCode == 404) return false;
    await _json(r);
    return true;
  }

  /// One sign-in attempt now: whether it worked, and the outcome in plain words.
  Future<({bool ok, String result})> test(String id) async {
    final j = await _json(await _c.post(Uri.parse('$base/v1/accounts/${Uri.encodeComponent(id)}/test'), headers: _headers).timeout(const Duration(seconds: 40)));
    return (ok: j['ok'] == true, result: '${j['result'] ?? ''}');
  }

  /// Tries a line's details before it is saved: adds it signed out (so it never takes calls),
  /// tests the sign-in, then removes it again.
  Future<({bool ok, String result})> tryLine(SipLine line, {required String tempId}) async {
    try {
      await put(tempId, line.toGatewayAccount(on: false));
    } on SipGatewayError catch (e) {
      return (ok: false, result: e.message);
    }
    try {
      return await test(tempId);
    } finally {
      try {
        await delete(tempId);
      } catch (_) {}
    }
  }

  void close() => _c.close();
}

class SipGatewayError implements Exception {
  SipGatewayError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// The gateway's source files, carried in the app as assets of the `localailine_sipgw` package
/// (its pubspec.yaml lists the same files). The app writes them out and builds them with Go.
const sipGatewaySources = [
  'go.mod',
  'go.sum',
  'cmd/sipgw/main.go',
  'internal/account/account.go',
  'internal/account/e164.go',
  'internal/account/registry.go',
  'internal/api/api.go',
  'internal/bridge/call.go',
  'internal/bridge/dialog.go',
  'internal/bridge/inbound.go',
  'internal/bridge/leg.go',
  'internal/bridge/trust.go',
  'internal/config/config.go',
  'internal/digest/digest.go',
  'internal/dnscache/dnscache.go',
  'internal/gateway/gateway.go',
  'internal/metrics/metrics.go',
  'internal/outbound/addr.go',
  'internal/outbound/outbound.go',
  'internal/ratelimit/ratelimit.go',
  'internal/registrar/registrar.go',
  'internal/sipx/log.go',
  'internal/sipx/sipx.go',
  'internal/store/store.go',
  'internal/stun/stun.go',
];
