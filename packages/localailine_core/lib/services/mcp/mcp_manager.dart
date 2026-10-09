import 'dart:convert';
import 'dart:io';

import 'package:localailine_core/notifier.dart';
import 'package:localailine_model/api.dart';

import '../../data/db.dart';
import 'mcp_auth.dart';
import 'mcp_client.dart';
import 'package:localailine_model/mcp.dart';
export 'package:localailine_model/mcp.dart' show McpAuthMode, McpStatus, McpServer;

/// Connects to the user's MCP servers and keeps sessions open.
class McpManager extends Notifier implements McpApi {
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
      // Only apps built here may run tools without asking.
      final builtHere = s.secret['app'] != null;
      final tools = [for (final t in await session.listTools()) builtHere || !t.autoApprove ? t : t.withoutAutoApprove()];
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

  /// MCP servers that run as programs on this machine. Off when the engine runs on a
  /// server for someone else: their programs would run on that server.
  bool allowLocalPrograms = true;

  /// On a server: servers added by the user may only be on the public internet, not on the server's
  /// own network (its internal services, cloud metadata). The engine's own business apps are allowed.
  bool publicTargetsOnly = false;

  static bool _privateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || !h.contains('.')) return true;
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 || b[0] == 0 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] >= 64 && b[1] < 128);
    }
    return (b[0] & 0xfe) == 0xfc; // unique local fc00::/7
  }

  /// Why this server can't be used here, or null when it can.
  Future<String?> _refusal(McpServer s) async {
    if (s.kind == 'stdio') return allowLocalPrograms ? null : 'MCP servers that run as programs aren’t available here. Connect one by its web address.';
    if (!publicTargetsOnly || s.secret['app'] != null) return null;
    final u = Uri.tryParse(s.target);
    if (u == null || u.scheme != 'https') return 'Use an https:// address for this MCP server.';
    if (_privateHost(u.host)) return 'That address is on a private network and can’t be reached from here.';
    try {
      for (final a in await InternetAddress.lookup(u.host)) {
        if (_privateHost(a.address)) return 'That address is on a private network and can’t be reached from here.';
      }
    } catch (_) {}
    return null;
  }

  Future<McpSession> _open(McpServer s, {required bool interactive}) async {
    final no = await _refusal(s);
    if (no != null) throw McpError(no);
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
        return attempt({
          if ((h['header'] ?? '').toString().isNotEmpty) h['header'] as String: (h['value'] ?? '') as String,
          // Several headers (e.g. a built app's tool key and the manager PIN).
          if (h['headers'] is Map) for (final e in (h['headers'] as Map).entries) '${e.key}': '${e.value}',
        });
      case McpAuthMode.auto:
        var auth = McpAuthState.fromJson(s.secret);
        if (auth.hasToken && auth.expired) {
          final r = await oauth.refresh(auth);
          if (r != null) {
            auth = r;
            await _save(s.id, {'secret': jsonEncode(auth.toJson())});
          }
        }
        // Services like Google answer without a login but refuse every tool: sign in first.
        if (auth.preset != null && !auth.hasToken) {
          if (!interactive) throw McpNeedsAuth(null);
          final fresh = await oauth.signIn(s.target, null, auth);
          await _save(s.id, {'secret': jsonEncode(fresh.toJson())});
          return attempt({'Authorization': 'Bearer ${fresh.accessToken}'});
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
    // Keep a known sign-in setup (e.g. the Google client), drop the login itself.
    final preset = (await _get(id))?.secret['preset'];
    await _save(id, {'secret': preset == null ? null : jsonEncode({'preset': preset}), 'status': 'needs_sign_in', 'tools': null});
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
