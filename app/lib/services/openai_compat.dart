import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/db.dart';
import 'cloud_llm.dart' show CloudConfig, CloudError;
import 'ollama.dart' show ChatMessage;

/// Programs that run AI models and answer in OpenAI's format. The user picks one and we fill in
/// the address it usually has; any other OpenAI-compatible server works with "Other".
enum ServerKind {
  vllm('vLLM', 'http://127.0.0.1:8000/v1'),
  lmStudio('LM Studio', 'http://127.0.0.1:1234/v1'),
  llamaCpp('llama.cpp server', 'http://127.0.0.1:8080/v1'),
  mlx('MLX (mlx_lm.server)', 'http://127.0.0.1:8080/v1'),
  localAi('LocalAI', 'http://127.0.0.1:8080/v1'),
  jan('Jan', 'http://127.0.0.1:1337/v1'),
  ollama('Ollama (OpenAI mode)', 'http://127.0.0.1:11434/v1'),
  other('Other', '');

  const ServerKind(this.label, this.defaultUrl);
  final String label, defaultUrl;

  static ServerKind parse(String? s) => ServerKind.values.where((k) => k.name == s).firstOrNull ?? ServerKind.other;
}

/// An AI server the user runs themselves (vLLM, LM Studio, llama.cpp…), spoken to in OpenAI's format.
class OpenAiServer {
  OpenAiServer({required this.baseUrl, this.apiKey = '', this.model = '', this.kind = ServerKind.other, this.maxCtx = 16384, this.disableThinking = false});

  /// e.g. http://127.0.0.1:8000/v1 (a missing /v1 is added).
  final String baseUrl;
  final String apiKey, model;
  final ServerKind kind;

  /// How much the server holds per request (its own setting; we only size what we send by it).
  final int maxCtx;

  /// Ask models that can think out loud (e.g. Qwen3) not to: phone replies must start quickly.
  final bool disableThinking;

  /// The address, always ending in /v1 and without a trailing slash.
  String get base {
    var b = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) return b;
    if (!b.startsWith('http')) b = 'http://$b';
    b = b.replaceAll(RegExp(r'/chat/completions$'), '');
    return RegExp(r'/v\d+$').hasMatch(b) ? b : '$b/v1';
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      };

  Map<String, Object> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'kind': kind.name,
        'maxCtx': maxCtx,
        'disableThinking': disableThinking,
      };

  static OpenAiServer? fromJson(Map<String, dynamic>? j) {
    final url = j?['baseUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    return OpenAiServer(
      baseUrl: url,
      apiKey: j!['apiKey'] as String? ?? '',
      model: j['model'] as String? ?? '',
      kind: ServerKind.parse(j['kind'] as String?),
      maxCtx: (j['maxCtx'] as num?)?.toInt() ?? 16384,
      disableThinking: j['disableThinking'] == true,
    );
  }

  OpenAiServer copyWith({String? model, int? maxCtx, bool? disableThinking}) => OpenAiServer(
      baseUrl: baseUrl, apiKey: apiKey, model: model ?? this.model, kind: kind, maxCtx: maxCtx ?? this.maxCtx, disableThinking: disableThinking ?? this.disableThinking);
}

/// One streamed reply, put back together: the text, any tool calls (which arrive in pieces,
/// numbered, across many chunks) and why the model stopped.
class StreamedReply {
  final text = StringBuffer();
  final _calls = <int, Map<String, Object?>>{};
  String? finishReason;

  /// Tool calls, complete, in the order the model made them.
  List<Map<String, Object?>> get toolCalls {
    final keys = _calls.keys.toList()..sort();
    return [
      for (final k in keys)
        {
          'id': _calls[k]!['id'] ?? 'call_$k',
          'type': 'function',
          'function': {'name': _calls[k]!['name'] ?? '', 'arguments': _calls[k]!['arguments'] ?? ''},
        }
    ];
  }

  /// Reads one `data:` line of the stream. Returns new answer text, if any.
  String? add(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    final j = jsonDecode(data);
    if (j is! Map) return null;
    if (j['error'] != null) {
      final e = j['error'];
      throw CloudError('Model error: ${e is Map ? e['message'] ?? e : e}');
    }
    final choice = (j['choices'] as List?)?.firstOrNull as Map?;
    if (choice == null) return null;
    finishReason = choice['finish_reason'] as String? ?? finishReason;
    final delta = (choice['delta'] ?? choice['message']) as Map?;
    if (delta == null) return null;
    for (final c in (delta['tool_calls'] as List?) ?? const []) {
      final i = (c['index'] as num?)?.toInt() ?? _calls.length;
      final slot = _calls.putIfAbsent(i, () => {});
      if (c['id'] != null) slot['id'] = c['id'];
      final f = c['function'] as Map?;
      if (f?['name'] != null) slot['name'] = '${slot['name'] ?? ''}${f!['name']}';
      final a = f?['arguments'];
      if (a != null) slot['arguments'] = '${slot['arguments'] ?? ''}${a is String ? a : jsonEncode(a)}';
    }
    // Thinking (reasoning_content) is not part of the answer.
    final piece = delta['content'];
    if (piece is String && piece.isNotEmpty) {
      text.write(piece);
      return piece;
    }
    return null;
  }

  /// The answer without any `<think>…</think>` part.
  String get answer => stripThink(text.toString());

  static String stripThink(String s) {
    s = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final open = s.indexOf('<think>');
    return (open >= 0 ? s.substring(0, open) : s).trim();
  }

  /// Stopped because it hit the length cap.
  bool get cutOff => finishReason == 'length';
}

/// Talks to any OpenAI-compatible server: LocalAILine's own engine, vLLM, LM Studio, llama.cpp…
class OpenAiCompat {
  OpenAiCompat({http.Client? client}) : _c = client ?? http.Client();
  final http.Client _c;

  /// The models the server offers (ids for the `model` field).
  Future<List<String>> models(OpenAiServer s) async {
    if (s.base.isEmpty) throw CloudError('Type the server’s address first.');
    http.Response r;
    try {
      r = await _c.get(Uri.parse('${s.base}/models'), headers: s.headers).timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw CloudError('No answer from ${s.base}. Is the server running?');
    } catch (e) {
      throw CloudError('Couldn’t reach ${s.base}. Is the server running? ($e)');
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw CloudError('The server refused the API key.');
    if (r.statusCode != 200) throw CloudError('The server answered with error ${r.statusCode}.');
    final j = jsonDecode(r.body);
    final list = j is Map ? (j['data'] as List? ?? j['models'] as List? ?? const []) : (j is List ? j : const []);
    return [
      for (final m in list)
        if (m is Map && (m['id'] ?? m['name'] ?? m['model']) != null) '${m['id'] ?? m['name'] ?? m['model']}'
        else if (m is String) m
    ].where((id) => !RegExp(r'embed', caseSensitive: false).hasMatch(id)).toList();
  }

  /// Checks the server answers a one-word question. Returns the reply.
  Future<String> test(OpenAiServer s) async {
    final b = StringBuffer();
    await for (final t in chat(s, [ChatMessage('user', 'Say OK.')], maxTokens: 16).timeout(const Duration(seconds: 60))) {
      b.write(t);
    }
    return b.toString();
  }

  /// The request body for a reply, shared by plain chat and tool use.
  static Map<String, Object?> body(OpenAiServer s, List<Map<String, Object?>> messages,
          {List<Object?> tools = const [], int? maxTokens, double? temperature, bool json = false, Map<String, Object?>? schema, int? seed, bool stream = true}) =>
      {
        'model': s.model.isEmpty ? 'default' : s.model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
        'stream': stream,
        'max_tokens': ?maxTokens,
        'temperature': ?temperature,
        'seed': ?seed,
        if (schema != null)
          'response_format': {'type': 'json_schema', 'json_schema': {'name': 'answer', 'schema': schema}}
        else if (json)
          'response_format': {'type': 'json_object'},
        // llama.cpp and vLLM read this; other servers ignore it.
        if (s.disableThinking) 'chat_template_kwargs': {'enable_thinking': false},
        // (llama.cpp and vLLM keep what they have read for the next request by themselves, as long as
        // the start of the conversation stays the same: so messages always go in the same order.)
      };

  /// Messages in OpenAI's format (pictures as data URLs).
  static List<Map<String, Object?>> wire(List<ChatMessage> messages) => [
        for (final m in messages)
          m.images.isEmpty
              ? m.toJson()
              : {
                  'role': m.role,
                  'content': [
                    {'type': 'text', 'text': m.content},
                    for (final i in m.images) {'type': 'image_url', 'image_url': {'url': 'data:${ChatMessage.mimeOf(i)};base64,$i'}},
                  ],
                },
      ];

  /// Sends one request and reads the streamed reply. [onPiece] gets each new bit of answer text.
  Future<StreamedReply> send(OpenAiServer s, Map<String, Object?> body, {void Function(String piece, StreamedReply so)? onPiece}) async {
    http.Request req() => http.Request('POST', Uri.parse('${s.base}/chat/completions'))
      ..headers.addAll(s.headers)
      ..body = jsonEncode(body);
    http.StreamedResponse res;
    try {
      res = await _c.send(req()).timeout(const Duration(minutes: 3));
    } on http.ClientException catch (e) {
      // llama.cpp's server closes the connection after a streamed reply; the next request may
      // try that closed connection first. Nothing was read yet, so asking again is safe.
      if (!RegExp(r'closed before full header|reset by peer|Broken pipe', caseSensitive: false).hasMatch(e.message)) rethrow;
      res = await _c.send(req()).timeout(const Duration(minutes: 3));
    }
    if (res.statusCode != 200) {
      final b = await res.stream.bytesToString();
      var detail = b;
      try {
        final j = jsonDecode(b);
        detail = '${(j['error'] is Map ? j['error']['message'] : j['error']) ?? b}';
      } catch (_) {}
      throw CloudError('Model error ${res.statusCode}: ${detail.length > 300 ? detail.substring(0, 300) : detail}');
    }
    final out = StreamedReply();
    if (body['stream'] == false) {
      out.add('data: ${await res.stream.bytesToString()}');
      return out;
    }
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final piece = out.add(line);
      if (piece != null) onPiece?.call(piece, out);
    }
    return out;
  }

  /// Streams the reply text (thinking left out).
  Stream<String> chat(OpenAiServer s, List<ChatMessage> messages, {bool json = false, double? temperature, int? maxTokens}) {
    final ctl = StreamController<String>();
    var shown = 0;
    send(s, body(s, wire(messages), json: json, temperature: temperature, maxTokens: maxTokens), onPiece: (_, so) {
      // Only text outside the thinking part, as it arrives.
      final clean = so.text.toString().contains('<think>') ? StreamedReply.stripThink(so.text.toString()) : so.text.toString().trimLeft();
      if (clean.length > shown) {
        ctl.add(clean.substring(shown));
        shown = clean.length;
      }
    }).then((_) => ctl.close(), onError: (Object e, StackTrace st) {
      ctl.addError(e, st);
      ctl.close();
    });
    return ctl.stream;
  }
}

/// Which AI the app thinks with, as saved in the settings:
/// 'local' = Ollama (the original setting name), 'builtin' = LocalAILine's own engine,
/// 'openai' = the user's own OpenAI-compatible server, 'cloud' = a cloud provider.
class LlmSettings {
  LlmSettings({this.source = 'local', this.server, this.builtinModel, this.cloud});
  String source;
  OpenAiServer? server;

  /// The built-in engine's model: a file in its models folder, or a full path (e.g. an Ollama download).
  String? builtinModel;
  CloudConfig? cloud;

  static const sources = ['builtin', 'local', 'openai', 'cloud'];

  static Future<LlmSettings> load(Db db) async {
    final s = LlmSettings(source: await db.setting('llm.source') ?? 'local');
    final cj = await db.setting('llm.cloud');
    s.cloud = cj == null || cj.isEmpty ? null : CloudConfig.fromJson(jsonDecode(cj) as Map<String, dynamic>);
    final oj = await db.setting('llm.openai');
    s.server = oj == null || oj.isEmpty ? null : OpenAiServer.fromJson(jsonDecode(oj) as Map<String, dynamic>);
    final b = await db.setting('llm.builtin');
    s.builtinModel = b == null || b.isEmpty ? null : b;
    // A choice that can't work any more falls back to Ollama, as before.
    if (!sources.contains(s.source) || (s.source == 'cloud' && s.cloud == null) || (s.source == 'openai' && s.server == null)) s.source = 'local';
    return s;
  }

  Future<void> save(Db db) async {
    await db.setSetting('llm.source', source);
    await db.setSetting('llm.openai', server == null ? '' : jsonEncode(server!.toJson()));
    await db.setSetting('llm.builtin', builtinModel ?? '');
    await db.setSetting('llm.cloud', cloud == null ? '' : jsonEncode(cloud!.toJson()));
  }
}

/// Debug builds: which AI to use for an automated test run, from LOCALAILINE_LLM:
/// `ollama:<model>`, `builtin:<model-id or .gguf path>` or `openai:<base-url>|<model>`.
class LlmOverride {
  LlmOverride(this.source, this.value, [this.model = '']);
  final String source, value, model;

  static LlmOverride? parse(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final i = s.indexOf(':');
    if (i < 0) return null;
    final kind = s.substring(0, i).trim(), rest = s.substring(i + 1).trim();
    switch (kind) {
      case 'ollama':
        return rest.isEmpty ? null : LlmOverride('local', rest);
      case 'builtin':
        return rest.isEmpty ? null : LlmOverride('builtin', rest);
      case 'openai':
        final bar = rest.lastIndexOf('|');
        final url = bar < 0 ? rest : rest.substring(0, bar);
        return url.isEmpty ? null : LlmOverride('openai', url, bar < 0 ? '' : rest.substring(bar + 1));
    }
    return null;
  }
}
