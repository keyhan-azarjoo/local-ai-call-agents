import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A tool offered by an MCP server.
class McpTool {
  McpTool({required this.name, required this.description, required this.inputSchema, required this.readOnly, this.title});
  final String name, description;
  final String? title;
  final Map<String, dynamic> inputSchema;

  /// From the server's `readOnlyHint`. Anything else asks before running.
  final bool readOnly;

  Map<String, Object?> toJson() =>
      {'name': name, 'description': description, 'inputSchema': inputSchema, 'readOnly': readOnly, 'title': title};

  static McpTool fromJson(Map<String, dynamic> j) => McpTool(
        name: j['name'] as String,
        title: j['title'] as String? ?? j['annotations']?['title'] as String?,
        description: (j['description'] as String?) ?? '',
        inputSchema: (j['inputSchema'] as Map?)?.cast<String, dynamic>() ?? {'type': 'object', 'properties': {}},
        readOnly: (j['readOnly'] as bool?) ?? (j['annotations']?['readOnlyHint'] == true),
      );
}

/// The server wants a login. [challenge] is its WWW-Authenticate header.
class McpNeedsAuth implements Exception {
  McpNeedsAuth(this.challenge);
  final String? challenge;
  @override
  String toString() => 'This server needs you to sign in.';
}

class McpError implements Exception {
  McpError(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class McpTransport {
  Future<Map<String, dynamic>> request(String method, Map<String, Object?> params);
  Future<void> notify(String method, Map<String, Object?> params);
  Future<void> close();
}

const _protocol = '2025-06-18';

/// Streamable HTTP transport (current MCP spec).
class HttpTransport implements McpTransport {
  HttpTransport(this.url, {this.headers = const {}, http.Client? client}) : _c = client ?? http.Client();
  final String url;
  final Map<String, String> headers;
  final http.Client _c;
  String? _session;
  bool initialized = false;
  int _id = 0;

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (initialized) 'MCP-Protocol-Version': _protocol,
        'Mcp-Session-Id': ?_session,
        ...headers,
      };

  Future<http.StreamedResponse> _post(Map<String, Object?> body) async {
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll(_h)
      ..body = jsonEncode(body);
    final res = await _c.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      await res.stream.drain<void>();
      throw McpNeedsAuth(res.headers['www-authenticate']);
    }
    final sid = res.headers['mcp-session-id'];
    if (sid != null) _session = sid;
    return res;
  }

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, Object?> params) async {
    final id = ++_id;
    final res = await _post({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    if (res.statusCode == 404 && _session != null) throw McpError('The server ended the session. Connect again.');
    if (res.statusCode >= 400) {
      final body = await res.stream.bytesToString();
      throw McpError('Server said ${res.statusCode}${body.isEmpty ? '' : ': ${body.length > 200 ? body.substring(0, 200) : body}'}');
    }
    final type = res.headers['content-type'] ?? '';
    Map<String, dynamic>? msg;
    if (type.contains('text/event-stream')) {
      await for (final m in _sse(res.stream)) {
        if (m['id'] == id) {
          msg = m;
          break;
        }
      }
    } else {
      final body = await res.stream.bytesToString();
      final j = jsonDecode(body);
      msg = (j is List ? j.firstWhere((e) => e['id'] == id, orElse: () => null) : j) as Map<String, dynamic>?;
    }
    if (msg == null) throw McpError('No reply from the server for $method.');
    if (msg['error'] != null) throw McpError('${msg['error']['message'] ?? msg['error']}');
    return (msg['result'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> notify(String method, Map<String, Object?> params) async {
    final res = await _post({'jsonrpc': '2.0', 'method': method, 'params': params});
    await res.stream.drain<void>();
  }

  @override
  Future<void> close() async {
    if (_session != null) {
      try {
        await _c.delete(Uri.parse(url), headers: _h).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }
}

/// Parses JSON messages out of a Server-Sent Events stream.
Stream<Map<String, dynamic>> _sse(Stream<List<int>> bytes) async* {
  final data = StringBuffer();
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      data.write(line.substring(5).trimLeft());
    } else if (line.isEmpty && data.isNotEmpty) {
      try {
        final j = jsonDecode(data.toString());
        if (j is Map<String, dynamic>) yield j;
      } catch (_) {}
      data.clear();
    }
  }
}

/// Older HTTP+SSE transport (MCP 2024-11-05): GET opens an event stream that
/// announces where to POST; replies arrive on the stream.
class SseTransport implements McpTransport {
  SseTransport(this.url, {this.headers = const {}});
  final String url;
  final Map<String, String> headers;
  final _c = http.Client();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  String? _post;
  int _id = 0;
  StreamSubscription? _sub;

  Future<void> open() async {
    final req = http.Request('GET', Uri.parse(url))..headers.addAll({'Accept': 'text/event-stream', ...headers});
    final res = await _c.send(req).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) throw McpNeedsAuth(res.headers['www-authenticate']);
    if (res.statusCode != 200) throw McpError('Server said ${res.statusCode}.');
    final endpoint = Completer<String>();
    String? event;
    final data = StringBuffer();
    _sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trimLeft());
      } else if (line.isEmpty && data.isNotEmpty) {
        final d = data.toString();
        data.clear();
        if (event == 'endpoint') {
          if (!endpoint.isCompleted) endpoint.complete(Uri.parse(url).resolve(d).toString());
        } else {
          try {
            final j = jsonDecode(d) as Map<String, dynamic>;
            final c = _pending.remove(j['id']);
            c?.complete(j);
          } catch (_) {}
        }
        event = null;
      }
    });
    _post = await endpoint.future.timeout(const Duration(seconds: 15), onTimeout: () => throw McpError('The server did not start an MCP session.'));
  }

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, Object?> params) async {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    final r = await _c.post(Uri.parse(_post!),
        headers: {'Content-Type': 'application/json', ...headers},
        body: jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    if (r.statusCode == 401) throw McpNeedsAuth(r.headers['www-authenticate']);
    final msg = await c.future.timeout(const Duration(seconds: 60), onTimeout: () => throw McpError('No reply for $method.'));
    if (msg['error'] != null) throw McpError('${msg['error']['message'] ?? msg['error']}');
    return (msg['result'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> notify(String method, Map<String, Object?> params) async {
    await _c.post(Uri.parse(_post!),
        headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _c.close();
  }
}

/// Local command transport: newline-delimited JSON-RPC over stdin/stdout.
class StdioTransport implements McpTransport {
  StdioTransport(this.command, {this.env = const {}});
  final String command;
  final Map<String, String> env;
  Process? _p;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _stderr = StringBuffer();
  int _id = 0;

  Future<void> open() async {
    // GUI apps get a short PATH; add the usual tool folders so `npx`/`uvx` work.
    final path = [
      Platform.environment['PATH'] ?? '',
      if (!Platform.isWindows) ...['/opt/homebrew/bin', '/usr/local/bin', '${Platform.environment['HOME']}/.local/bin'],
    ].join(Platform.isWindows ? ';' : ':');
    _p = await Process.start(
      Platform.isWindows ? 'cmd' : '/bin/sh',
      Platform.isWindows ? ['/c', command] : ['-c', command],
      environment: {...env, 'PATH': path},
    );
    _p!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;
        _pending.remove(j['id'])?.complete(j);
      } catch (_) {}
    });
    _p!.stderr.transform(utf8.decoder).listen((s) {
      if (_stderr.length < 4000) _stderr.write(s);
    });
    _p!.exitCode.then((code) {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(McpError('The command stopped (exit $code). ${_stderr.toString().trim().split('\n').lastOrNull ?? ''}'));
      }
      _pending.clear();
    });
  }

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, Object?> params) async {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _p!.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    final msg = await c.future.timeout(const Duration(seconds: 60), onTimeout: () => throw McpError('No reply for $method.'));
    if (msg['error'] != null) throw McpError('${msg['error']['message'] ?? msg['error']}');
    return (msg['result'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> notify(String method, Map<String, Object?> params) async {
    _p!.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}));
  }

  @override
  Future<void> close() async => _p?.kill();
}

/// One connected MCP server.
class McpSession {
  McpSession(this.transport);
  final McpTransport transport;
  String serverName = '';

  Future<void> initialize() async {
    final r = await transport.request('initialize', {
      'protocolVersion': _protocol,
      'capabilities': {},
      'clientInfo': {'name': 'LocalAILine', 'version': '0.1.0'},
    });
    serverName = (r['serverInfo']?['name'] as String?) ?? '';
    if (transport is HttpTransport) (transport as HttpTransport).initialized = true;
    await transport.notify('notifications/initialized', {});
  }

  Future<List<McpTool>> listTools() async {
    final out = <McpTool>[];
    String? cursor;
    do {
      final r = await transport.request('tools/list', {'cursor': ?cursor});
      for (final t in (r['tools'] as List? ?? [])) {
        out.add(McpTool.fromJson((t as Map).cast<String, dynamic>()));
      }
      cursor = r['nextCursor'] as String?;
    } while (cursor != null && out.length < 500);
    return out;
  }

  /// Runs a tool and returns its text output.
  Future<({String text, bool isError})> callTool(String name, Map<String, dynamic> args) async {
    final r = await transport.request('tools/call', {'name': name, 'arguments': args});
    final parts = <String>[];
    for (final c in (r['content'] as List? ?? [])) {
      if (c['type'] == 'text') {
        parts.add(c['text'] as String);
      } else if (c['type'] == 'resource') {
        parts.add('${c['resource']?['text'] ?? c['resource']?['uri'] ?? ''}');
      } else {
        parts.add('[${c['type']} content]');
      }
    }
    if (parts.isEmpty && r['structuredContent'] != null) parts.add(jsonEncode(r['structuredContent']));
    return (text: parts.join('\n'), isError: r['isError'] == true);
  }

  Future<void> close() => transport.close();
}
