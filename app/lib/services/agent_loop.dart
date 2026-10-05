import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_llm.dart';
import 'mcp/mcp_client.dart';
import 'ollama.dart' show ChatMessage;

/// An MCP tool as offered to the model.
class ToolBinding {
  ToolBinding({required this.serverId, required this.serverName, required this.tool, required this.fnName});
  final int serverId;
  final String serverName;
  final McpTool tool;

  /// Name the model sees: provider-safe, unique across servers.
  final String fnName;

  static String safeName(String server, String tool) {
    String clean(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final n = '${clean(server).toLowerCase()}__${clean(tool)}';
    return n.length <= 64 ? n : n.substring(0, 64);
  }
}

/// What happened when the AI used a tool, for showing in the conversation.
class ToolEvent {
  ToolEvent(this.binding, this.args, {this.result = '', this.ok = true, this.denied = false});
  final ToolBinding binding;
  final Map<String, dynamic> args;
  String result;
  bool ok, denied;
}

typedef Approver = Future<bool> Function(ToolBinding b, Map<String, dynamic> args);
typedef ToolRunner = Future<({String text, bool isError})> Function(ToolBinding b, Map<String, dynamic> args);

/// Where the model runs.
sealed class ModelTarget {}

class LocalTarget extends ModelTarget {
  LocalTarget(this.model, {this.base = 'http://127.0.0.1:11434', this.disableThinking = false});
  final String model, base;
  final bool disableThinking;
}

class CloudTarget extends ModelTarget {
  CloudTarget(this.config);
  final CloudConfig config;
}

/// Runs the model, executes the tools it asks for, and loops until it answers.
class ToolLoop {
  ToolLoop({http.Client? client}) : _c = client ?? http.Client();
  final http.Client _c;

  static const maxRounds = 6;
  static const _maxResult = 12000;

  Future<String> run({
    required ModelTarget target,
    required List<ChatMessage> messages,
    required List<ToolBinding> tools,
    required Approver approve,
    required ToolRunner runTool,
    void Function(ToolEvent)? onEvent,
  }) async {
    final byName = {for (final t in tools) t.fnName: t};

    Future<(String, bool)> exec(String name, Map<String, dynamic> args) async {
      final b = byName[name];
      if (b == null) return ('Unknown tool $name.', true);
      final ev = ToolEvent(b, args);
      if (!b.tool.readOnly && !await approve(b, args)) {
        ev
          ..denied = true
          ..ok = false
          ..result = 'The user declined this action.';
        onEvent?.call(ev);
        return (ev.result, true);
      }
      try {
        final r = await runTool(b, args);
        ev
          ..result = r.text
          ..ok = !r.isError;
      } catch (e) {
        ev
          ..result = 'Tool failed: $e'
          ..ok = false;
      }
      onEvent?.call(ev);
      final text = ev.result.length > _maxResult ? '${ev.result.substring(0, _maxResult)}\n…(truncated)' : ev.result;
      return (text, !ev.ok);
    }

    return switch (target) {
      LocalTarget t => _ollama(t, messages, tools, exec),
      CloudTarget t => switch (t.config.provider) {
          CloudProvider.openai || CloudProvider.azure => _openai(t.config, messages, tools, exec),
          CloudProvider.anthropic => _anthropic(t.config, messages, tools, exec),
          CloudProvider.google => _google(t.config, messages, tools, exec),
        },
    };
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, String> headers, Object body) async {
    final r = await _c
        .post(Uri.parse(url), headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode(body))
        .timeout(const Duration(minutes: 3));
    if (r.statusCode != 200) {
      var detail = r.body;
      try {
        final j = jsonDecode(r.body);
        detail = (j['error']?['message'] ?? j['error'] ?? r.body).toString();
      } catch (_) {}
      throw CloudError('Model error ${r.statusCode}: ${detail.length > 300 ? detail.substring(0, 300) : detail}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Map<String, Object?> _fn(ToolBinding b) => {
        'type': 'function',
        'function': {
          'name': b.fnName,
          'description': _describe(b),
          'parameters': b.tool.inputSchema,
        },
      };

  static String _describe(ToolBinding b) =>
      '${b.tool.description.isEmpty ? b.tool.name : b.tool.description} (from ${b.serverName}${b.tool.readOnly ? '' : '; changes data, the user must approve'})';

  static Map<String, dynamic> _args(Object? a) {
    if (a is Map) return a.cast<String, dynamic>();
    if (a is String && a.trim().isNotEmpty) {
      try {
        return (jsonDecode(a) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    return {};
  }

  // ---------------- Ollama ----------------
  Future<String> _ollama(LocalTarget t, List<ChatMessage> messages, List<ToolBinding> tools,
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec) async {
    final msgs = <Map<String, Object?>>[for (final m in messages) m.toJson()];
    for (var round = 0; round < maxRounds; round++) {
      final r = await _post('${t.base}/api/chat', {}, {
        'model': t.model,
        'messages': msgs,
        if (tools.isNotEmpty) 'tools': tools.map(_fn).toList(),
        'stream': false,
        'keep_alive': -1,
        'think': ?(t.disableThinking ? false : null),
        'options': {'num_ctx': 8192, 'temperature': 0.4},
      });
      final m = (r['message'] as Map).cast<String, dynamic>();
      final calls = (m['tool_calls'] as List?) ?? [];
      if (calls.isEmpty) return _stripThink((m['content'] as String?) ?? '');
      msgs.add({'role': 'assistant', 'content': m['content'] ?? '', 'tool_calls': calls});
      for (final c in calls) {
        final name = c['function']['name'] as String;
        final (text, _) = await exec(name, _args(c['function']['arguments']));
        msgs.add({'role': 'tool', 'content': text, 'tool_name': name});
      }
    }
    return 'I used several tools but couldn’t finish. Try asking more specifically.';
  }

  static String _stripThink(String s) => s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();

  // ---------------- OpenAI / Azure ----------------
  Future<String> _openai(CloudConfig c, List<ChatMessage> messages, List<ToolBinding> tools,
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec) async {
    final azure = c.provider == CloudProvider.azure;
    final url = azure
        ? '${c.endpoint.replaceAll(RegExp(r'/+$'), '')}/openai/deployments/${c.model}/chat/completions?api-version=2024-10-21'
        : 'https://api.openai.com/v1/chat/completions';
    final headers = azure ? {'api-key': c.apiKey} : {'Authorization': 'Bearer ${c.apiKey}'};
    final msgs = <Map<String, Object?>>[for (final m in messages) m.toJson()];
    for (var round = 0; round < maxRounds; round++) {
      final r = await _post(url, headers, {
        if (!azure) 'model': c.model,
        'messages': msgs,
        if (tools.isNotEmpty) 'tools': tools.map(_fn).toList(),
      });
      final m = ((r['choices'] as List).first['message'] as Map).cast<String, dynamic>();
      final calls = (m['tool_calls'] as List?) ?? [];
      if (calls.isEmpty) return (m['content'] as String?) ?? '';
      msgs.add({'role': 'assistant', 'content': m['content'], 'tool_calls': calls});
      for (final call in calls) {
        final (text, _) = await exec(call['function']['name'] as String, _args(call['function']['arguments']));
        msgs.add({'role': 'tool', 'tool_call_id': call['id'], 'content': text});
      }
    }
    return 'I used several tools but couldn’t finish. Try asking more specifically.';
  }

  // ---------------- Anthropic ----------------
  Future<String> _anthropic(CloudConfig c, List<ChatMessage> messages, List<ToolBinding> tools,
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec) async {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n\n');
    final msgs = <Map<String, Object?>>[
      for (final m in messages.where((m) => m.role != 'system')) {'role': m.role, 'content': m.content}
    ];
    final effort = c.model.startsWith('claude-opus-5') || c.model.startsWith('claude-sonnet-5') || c.model.startsWith('claude-fable');
    for (var round = 0; round < maxRounds; round++) {
      final r = await _post('https://api.anthropic.com/v1/messages', {'x-api-key': c.apiKey, 'anthropic-version': '2023-06-01'}, {
        'model': c.model,
        'max_tokens': 8192,
        if (effort) 'output_config': {'effort': 'low'},
        if (system.isNotEmpty) 'system': system,
        'messages': msgs,
        if (tools.isNotEmpty)
          'tools': [
            for (final b in tools) {'name': b.fnName, 'description': _describe(b), 'input_schema': b.tool.inputSchema}
          ],
      });
      final content = (r['content'] as List).cast<Map<String, dynamic>>();
      final uses = content.where((b) => b['type'] == 'tool_use').toList();
      if (r['stop_reason'] != 'tool_use' || uses.isEmpty) {
        return content.where((b) => b['type'] == 'text').map((b) => b['text']).join().trim();
      }
      // Send the assistant turn back unchanged (thinking blocks included).
      msgs.add({'role': 'assistant', 'content': content});
      final results = <Map<String, Object?>>[];
      for (final u in uses) {
        final (text, isError) = await exec(u['name'] as String, _args(u['input']));
        results.add({'type': 'tool_result', 'tool_use_id': u['id'], 'content': text, if (isError) 'is_error': true});
      }
      msgs.add({'role': 'user', 'content': results});
    }
    return 'I used several tools but couldn’t finish. Try asking more specifically.';
  }

  // ---------------- Google ----------------
  Future<String> _google(CloudConfig c, List<ChatMessage> messages, List<ToolBinding> tools,
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec) async {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n\n');
    final contents = <Map<String, Object?>>[
      for (final m in messages.where((m) => m.role != 'system'))
        {
          'role': m.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m.content}
          ]
        }
    ];
    for (var round = 0; round < maxRounds; round++) {
      final r = await _post(
          'https://generativelanguage.googleapis.com/v1beta/models/${c.model}:generateContent', {'x-goog-api-key': c.apiKey}, {
        if (system.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': system}
            ]
          },
        'contents': contents,
        if (tools.isNotEmpty)
          'tools': [
            {
              'functionDeclarations': [
                for (final b in tools) {'name': b.fnName, 'description': _describe(b), 'parameters': geminiSchema(b.tool.inputSchema)}
              ]
            }
          ],
      });
      final content = ((r['candidates'] as List?)?.firstOrNull?['content'] as Map?)?.cast<String, dynamic>();
      final parts = ((content?['parts'] as List?) ?? []).cast<Map<String, dynamic>>();
      final calls = parts.where((p) => p['functionCall'] != null).toList();
      if (calls.isEmpty) return parts.map((p) => p['text'] ?? '').join().trim();
      contents.add(content!);
      final responses = <Map<String, Object?>>[];
      for (final p in calls) {
        final name = p['functionCall']['name'] as String;
        final (text, _) = await exec(name, _args(p['functionCall']['args']));
        responses.add({
          'functionResponse': {
            'name': name,
            'response': {'result': text}
          }
        });
      }
      contents.add({'role': 'user', 'parts': responses});
    }
    return 'I used several tools but couldn’t finish. Try asking more specifically.';
  }

  /// Gemini accepts a subset of JSON Schema; drop what it rejects.
  static Object? geminiSchema(Object? s) {
    if (s is List) return s.map(geminiSchema).toList();
    if (s is! Map) return s;
    const keep = {'type', 'description', 'properties', 'required', 'items', 'enum', 'format', 'nullable', 'anyOf', 'minimum', 'maximum'};
    final out = <String, Object?>{};
    for (final e in s.entries) {
      final k = e.key as String;
      if (!keep.contains(k)) continue;
      if (k == 'properties' && e.value is Map) {
        out[k] = {for (final p in (e.value as Map).entries) p.key: geminiSchema(p.value)};
      } else if (k == 'type' && e.value is List) {
        final types = (e.value as List).where((t) => t != 'null').toList();
        out['type'] = types.isEmpty ? 'string' : types.first;
        if ((e.value as List).contains('null')) out['nullable'] = true;
      } else {
        out[k] = geminiSchema(e.value);
      }
    }
    return out;
  }
}
