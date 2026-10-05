import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/db.dart';
import 'mcp_auth.dart';
import 'mcp_client.dart';

/// How a server proves who we are.
/// auto  = sign in through the browser when the server asks (OAuth)
/// token = a fixed header, e.g. `Authorization: Bearer …` or `X-API-Key: …`
/// none  = no sign-in
enum McpAuthMode { auto, token, none }

enum McpStatus { unknown, connecting, connected, needsSignIn, error }

class McpServer {
  McpServer(this.row);
  final Map<String, Object?> row;
  int get id => row['id'] as int;
  String get name => row['name'] as String;
  String get kind => row['kind'] as String; // http | stdio
  String get target => row['target'] as String;
  String get scope => row['scope'] as String;
  bool get enabled => row['enabled'] == 1;
  McpAuthMode get authMode => McpAuthMode.values.firstWhere((m) => m.name == row['auth_mode'], orElse: () => McpAuthMode.auto);

  /// For token mode: {"header": "...", "value": "..."}; for auto: McpAuthState; for stdio: {"env": {...}}.
  Map<String, dynamic> get secret {
    final s = row['secret'] as String?;
    return s == null || s.isEmpty ? {} : (jsonDecode(s) as Map).cast<String, dynamic>();
  }

  List<McpTool> get tools {
    final t = row['tools'] as String?;
    return t == null || t.isEmpty ? [] : [for (final j in jsonDecode(t) as List) McpTool.fromJson((j as Map).cast<String, dynamic>())];
  }
}

/// Connects to the user's MCP servers and keeps sessions open.
class McpManager extends ChangeNotifier {
  McpManager(this.db, {required Future<void> Function(String) openBrowser}) : oauth = McpOAuth(openBrowser: openBrowser);
  final Db db;
  final McpOAuth oauth;
  final _sessions = <int, McpSession>{};
  final status = <int, McpStatus>{};
  final errors = <int, String>{};

  Future<List<McpServer>> servers() async => (await db.all('mcp_servers', orderBy: 'id')).map(McpServer.new).toList();

  Future<McpServer?> _get(int id) async {
    final r = await db.all('mcp_servers', where: 'id = ?', args: [id]);
    return r.isEmpty ? null : McpServer(r.first);
  }

  McpStatus statusOf(McpServer s) {
    final live = status[s.id];
    if (live != null) return live;
    return switch (s.row['status']) {
      'connected' => McpStatus.unknown, // was fine last time; reconnect on use
      'needs_sign_in' => McpStatus.needsSignIn,
      'error' => McpStatus.error,
      _ => McpStatus.unknown,
    };
  }

  String? errorOf(McpServer s) => errors[s.id] ?? (s.row['error'] as String?);

  Future<void> _save(int id, Map<String, Object?> fields) => db.update('mcp_servers', id, fields);

  void _set(int id, McpStatus st, [String? error]) {
    status[id] = st;
    if (error == null) {
      errors.remove(id);
    } else {
      errors[id] = error;
    }
    notifyListeners();
  }

  /// Connects and lists tools. With [interactive], opens the browser to sign in if needed.
  Future<void> connect(int id, {bool interactive = false}) async {
    final s = await _get(id);
    if (s == null) return;
    _set(id, McpStatus.connecting);
    await _sessions.remove(id)?.close();
    try {
      final session = await _open(s, interactive: interactive);
      final tools = await session.listTools();
      _sessions[id] = session;
      await _save(id, {'status': 'connected', 'error': null, 'tools': jsonEncode(tools.map((t) => t.toJson()).toList())});
      _set(id, McpStatus.connected);
    } on McpNeedsAuth {
      if (s.authMode == McpAuthMode.auto) {
        await _save(id, {'status': 'needs_sign_in', 'error': null});
        _set(id, McpStatus.needsSignIn);
      } else {
        const msg = 'The server rejected the API key or token. Check it with Edit.';
        await _save(id, {'status': 'error', 'error': msg});
        _set(id, McpStatus.error, msg);
      }
    } catch (e) {
      await _save(id, {'status': 'error', 'error': '$e'});
      _set(id, McpStatus.error, '$e');
    }
  }

  Future<McpSession> _open(McpServer s, {required bool interactive}) async {
    if (s.kind == 'stdio') {
      final env = (s.secret['env'] as Map?)?.cast<String, String>() ?? {};
      final t = StdioTransport(s.target, env: env);
      await t.open();
      final session = McpSession(t);
      await session.initialize();
      return session;
    }

    Future<McpSession> attempt(Map<String, String> headers) async {
      try {
        final session = McpSession(HttpTransport(s.target, headers: headers));
        await session.initialize();
        return session;
      } on McpError catch (e) {
        // Older servers only speak HTTP+SSE.
        if (!e.message.contains('404') && !e.message.contains('405')) rethrow;
        final t = SseTransport(s.target, headers: headers);
        await t.open();
        final session = McpSession(t);
        await session.initialize();
        return session;
      }
    }

    switch (s.authMode) {
      case McpAuthMode.none:
        return attempt({});
      case McpAuthMode.token:
        final h = s.secret;
        return attempt({if ((h['header'] ?? '').toString().isNotEmpty) h['header'] as String: (h['value'] ?? '') as String});
      case McpAuthMode.auto:
        var auth = McpAuthState.fromJson(s.secret);
        if (auth.hasToken && auth.expired) {
          final r = await oauth.refresh(auth);
          if (r != null) {
            auth = r;
            await _save(s.id, {'secret': jsonEncode(auth.toJson())});
          }
        }
        try {
          return await attempt({if (auth.hasToken) 'Authorization': 'Bearer ${auth.accessToken}'});
        } on McpNeedsAuth catch (e) {
          // Token rejected: try a refresh first, then a fresh sign-in.
          final r = auth.hasToken ? await oauth.refresh(auth) : null;
          if (r != null) {
            await _save(s.id, {'secret': jsonEncode(r.toJson())});
            try {
              return await attempt({'Authorization': 'Bearer ${r.accessToken}'});
            } on McpNeedsAuth {
              // fall through to sign-in
            }
          }
          if (!interactive) rethrow;
          final fresh = await oauth.signIn(s.target, e.challenge, auth);
          await _save(s.id, {'secret': jsonEncode(fresh.toJson())});
          return attempt({'Authorization': 'Bearer ${fresh.accessToken}'});
        }
    }
  }

  Future<void> signOut(int id) async {
    await _sessions.remove(id)?.close();
    await _save(id, {'secret': null, 'status': 'needs_sign_in', 'tools': null});
    _set(id, McpStatus.needsSignIn);
  }

  Future<void> disconnect(int id) async {
    await _sessions.remove(id)?.close();
    status.remove(id);
    notifyListeners();
  }

  // Read-only results reused for a few minutes: repeat questions are instant.
  final _cache = <String, (DateTime, ({String text, bool isError}))>{};
  static const cacheFor = Duration(minutes: 5);

  static String _key(int id, String tool, Map<String, dynamic> args) {
    final keys = args.keys.toList()..sort();
    return '$id|$tool|${jsonEncode({for (final k in keys) k: args[k]})}';
  }

  /// Like [call], but a read-only result from the last few minutes is returned instantly.
  Future<({String text, bool isError})> callCached(int id, String tool, Map<String, dynamic> args, {required bool readOnly}) async {
    if (!readOnly) {
      _cache.removeWhere((k, _) => k.startsWith('$id|')); // data may have changed
      return call(id, tool, args);
    }
    final k = _key(id, tool, args);
    final hit = _cache[k];
    if (hit != null && DateTime.now().difference(hit.$1) < cacheFor) return hit.$2;
    final r = await call(id, tool, args);
    if (!r.isError) _cache[k] = (DateTime.now(), r);
    return r;
  }

  /// Runs a tool, reconnecting (and refreshing the login) if needed.
  Future<({String text, bool isError})> call(int id, String tool, Map<String, dynamic> args) async {
    var session = _sessions[id];
    if (session == null) {
      await connect(id);
      session = _sessions[id];
      if (session == null) throw McpError(status[id] == McpStatus.needsSignIn ? 'Sign in to this server first (Tools).' : (errors[id] ?? 'Not connected.'));
    }
    try {
      return await session.callTool(tool, args);
    } on McpNeedsAuth {
      await connect(id);
      final again = _sessions[id];
      if (again == null) throw McpError('Sign in to this server again (Tools).');
      return again.callTool(tool, args);
    } on McpError catch (e) {
      if (!e.message.contains('session')) rethrow;
      await connect(id);
      return _sessions[id]!.callTool(tool, args);
    }
  }

  Future<void> closeAll() async {
    for (final s in _sessions.values) {
      await s.close();
    }
    _sessions.clear();
  }
}
