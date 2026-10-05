import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_llm.dart';
import 'mcp/mcp_client.dart';
import 'ollama.dart' show ChatMessage;
import 'tool_args.dart';
import 'tool_results.dart';

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
  LocalTarget(this.model, {this.base = 'http://127.0.0.1:11434', this.disableThinking = false, this.maxCtx = 32768});
  final String model, base;
  final bool disableThinking;

  /// Largest context this computer can hold for the model.
  final int maxCtx;
}

/// Picks the few tools that matter for a question, so small local models
/// aren't buried under every tool a server offers.
class ToolSelector {
  static const _stop = {
    'the', 'and', 'for', 'with', 'from', 'that', 'this', 'what', 'which', 'give', 'show', 'tell', 'please', 'can', 'you',
    'all', 'any', 'how', 'many', 'much', 'are', 'there', 'about', 'into', 'have', 'has', 'get', 'list', 'me', 'my', 'our',
  };

  static String _stem(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('ing')) return w.substring(0, w.length - 3);
    if (w.length > 3 && w.endsWith('es') && !w.endsWith('ses')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  static Set<String> words(String s, {bool keepCommon = false}) => {
        for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 2 && (keepCommon || !_stop.contains(w))) _stem(w)
      };

  static double score(Set<String> q, Set<String> verbs, ToolBinding b) {
    final name = words(b.tool.name.replaceAll('_', ' '), keepCommon: true);
    final title = words(b.tool.title ?? '');
    final desc = words(b.tool.description.length > 300 ? b.tool.description.substring(0, 300) : b.tool.description);
    final server = words(b.serverName);
    var sc = 0.0;
    for (final w in q) {
      if (name.contains(w)) sc += 4;
      if (title.contains(w)) sc += 2;
      if (desc.contains(w)) sc += 1;
      if (server.contains(w)) sc += .5;
    }
    // "list/get/count/how many" words favour matching tool verbs.
    for (final v in verbs) {
      if (name.contains(v)) sc += 1.5;
    }
    if (sc > 0 && b.tool.readOnly) sc += .25;
    return sc;
  }

  static List<ToolBinding> rank(String query, List<ToolBinding> tools, int k) {
    final q = words(query);
    final all = words(query, keepCommon: true);
    final verbs = {
      if (all.contains('list') || all.contains('show') || all.contains('all')) ...['list', 'query'],
      if (all.contains('how') && all.contains('many') || all.contains('count') || all.contains('number')) ...['count', 'query'],
      if (all.contains('get') || all.contains('find') || all.contains('detail')) ...['get', 'find', 'search'],
    };
    final scored = [for (final t in tools) (t, score(q, verbs, t))]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (t, sc) in scored.take(k)) if (sc > 0) t];
  }
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

  /// Added to the system prompt whenever tools are offered.
  static const toolRules = 'Rules for tool results: '
      '1) Never guess names or details that a result does not contain. If a result only has IDs (for example groupIds), '
      'look them up with another tool or show the ID. '
      '2) Always present the data you received. If a note says some items did not fit, still list the ones shown, '
      'then say how many more exist. '
      '3) If the user asks for a list, list every item (one line each), then add the totals. '
      '4) For counts, use the "Totals" line from the result exactly; never count by yourself. '
      '5) Inputs: use ids from earlier results (never names where an id is asked); write dates as YYYY-MM-DD. '
      '6) If a tool returns an error, read it, fix the inputs and try once more; if it still fails, explain the problem simply.';

  Future<String> run({
    required ModelTarget target,
    required List<ChatMessage> messages,
    required List<ToolBinding> tools,
    required Approver approve,
    required ToolRunner runTool,
    void Function(ToolEvent)? onEvent,
  }) async {
    final byName = {for (final t in tools) t.fnName: t};

    // Only the most relevant tools are offered; find_tools reaches the rest.
    final limit = target is LocalTarget ? 10 : 40;
    final resultLimit = switch (target) {
      LocalTarget t => t.maxCtx >= 16384 ? 14000 : 7000,
      CloudTarget _ => 40000,
    };
    if (tools.isNotEmpty) {
      final now = DateTime.now();
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final rules = 'Today is ${days[now.weekday - 1]} ${now.toIso8601String().substring(0, 10)}. $toolRules';
      final i = messages.indexWhere((m) => m.role == 'system');
      messages = [
        if (i < 0) ChatMessage('system', rules),
        for (var j = 0; j < messages.length; j++)
          j == i ? ChatMessage('system', '${messages[j].content}\n\n$rules') : messages[j],
      ];
    }
    final lastUser = messages.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage('user', '')).content;
    final recent = messages.where((m) => m.role == 'user').toList().reversed.take(3).map((m) => m.content).join(' ');
    final active = <ToolBinding>[
      ...ToolSelector.rank(lastUser, tools, limit),
    ];
    if (active.length < 4) {
      for (final t in ToolSelector.rank(recent, tools, limit)) {
        if (!active.contains(t)) active.add(t);
      }
    }
    if (tools.length <= limit) {
      active
        ..clear()
        ..addAll(tools);
    }
    final finder = tools.length > active.length
        ? ToolBinding(
            serverId: -1,
            serverName: 'LocalAILine',
            fnName: 'find_tools',
            tool: McpTool(
              name: 'find_tools',
              readOnly: true,
              description: 'Search the user’s connected tools by keywords (${tools.length} available from '
                  '${tools.map((t) => t.serverName).toSet().join(', ')}). Use it when none of the offered tools fit. '
                  'Matching tools become available to call.',
              inputSchema: {
                'type': 'object',
                'properties': {
                  'query': {'type': 'string', 'description': 'What you need, e.g. "list users" or "job weight"'}
                },
                'required': ['query'],
              },
            ),
          )
        : null;
    final offered = <ToolBinding>[...active, ?finder];
    final idCache = <String, Map<String, String>>{};
    final ids = IdMemory();
    String? pendingRetry; // a tool refused for bad inputs, not yet retried
    var nudged = false;
    String? nudge() {
      if (pendingRetry == null || nudged) return null;
      nudged = true;
      return 'You now have what you need. Call $pendingRetry again with the correct id or inputs, then answer my question.';
    }
    for (final m in messages) {
      ids.learn(m.content);
    }

    Future<(String, bool)> exec(String name, Map<String, dynamic> args) async {
      if (name == 'find_tools') {
        final found = ToolSelector.rank('${args['query'] ?? ''}', tools, 8);
        for (final f in found) {
          if (!offered.contains(f)) offered.insert(offered.length - 1, f);
        }
        return (
          found.isEmpty
              ? 'No matching tools. Try other words.'
              : 'Now available:\n${found.map((f) => '- ${f.fnName}: ${_short(f.tool.description, 120)}').join('\n')}',
          false
        );
      }
      final b = byName[name];
      if (b == null) return ('Unknown tool $name. Use find_tools to search.', true);
      if (!offered.contains(b)) offered.insert(offered.length - (finder == null ? 0 : 1), b);
      // Check the model's inputs first; don't send the server something it will reject.
      bool hasLookup(String entity) => ToolSelector.rank('list $entity', tools.where((t) => t.tool.readOnly).toList(), 1).isNotEmpty;
      final prepared = ToolArgs.prepare(b.tool.inputSchema, args,
          toolName: b.fnName,
          looksWrongId: (k, v) => ids.looksWrong(v, canLookUp: hasLookup(ToolArgs.entityOf(k))), lookupToolFor: (entity) {
        final t = ToolSelector.rank('list $entity', tools.where((t) => t.tool.readOnly).toList(), 1).firstOrNull;
        if (t != null && !offered.contains(t)) offered.insert(offered.length - (finder == null ? 0 : 1), t);
        return t?.fnName;
      });
      if (prepared.problem != null) {
        pendingRetry = b.fnName;
        onEvent?.call(ToolEvent(b, args, result: prepared.problem!, ok: false));
        return (prepared.problem!, true);
      }
      if (pendingRetry == b.fnName) pendingRetry = null;
      args = prepared.args;
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
        final failed = r.isError || ToolErrors.looksLikeError(r.text);
        ev
          ..result = failed
              ? ToolErrors.friendly(r.text)
              : r.text.trim().isEmpty || RegExp(r'^\{\s*"\w+"\s*:\s*null\s*\}$').hasMatch(r.text.trim())
                  ? 'The tool returned no data. If you passed an id, it may be wrong: get ids from a list tool first.'
                  : r.text
          ..ok = !failed;
        if (!failed) ids.learn(r.text);
      } catch (e) {
        ev
          ..result = ToolErrors.friendly('$e')
          ..ok = false;
      }
      onEvent?.call(ev);
      // Ids in the result (groupIds, teamId…): look their names up with a safe
      // list tool and write them next to the ids, so the model never guesses.
      final lookups = <String, Map<String, String>>{};
      if (ev.ok) {
        for (final entity in ToolResults.referencedEntities(ev.result).take(4)) {
          final known = idCache[entity];
          if (known != null) {
            lookups[entity] = known;
            continue;
          }
          final candidates = tools
              .where((t) =>
                  t != b &&
                  t.tool.readOnly &&
                  t.tool.name.toLowerCase().startsWith('list') &&
                  ToolSelector.words(t.tool.name.replaceAll('_', ' '), keepCommon: true).contains(entity) &&
                  ((t.tool.inputSchema['required'] as List?) ?? const []).isEmpty)
              .toList();
          final pick = ToolSelector.rank('list $entity', candidates, 1).firstOrNull;
          if (pick == null) continue;
          try {
            final r = await runTool(pick, {});
            onEvent?.call(ToolEvent(pick, {}, result: r.text, ok: !r.isError));
            final names = ToolResults.idNames(r.text);
            if (names.isNotEmpty) lookups[entity] = idCache[entity] = names;
          } catch (_) {}
        }
      }
      if (!ev.ok) return (ev.result, true);
      final fitted = ToolResults.compact(ev.result, resultLimit, lookups: lookups);
      return (fitted.text, false);
    }

    return switch (target) {
      LocalTarget t => _ollama(t, messages, offered, exec, nudge),
      CloudTarget t => switch (t.config.provider) {
          CloudProvider.openai || CloudProvider.azure => _openai(t.config, messages, offered, exec, nudge),
          CloudProvider.anthropic => _anthropic(t.config, messages, offered, exec, nudge),
          CloudProvider.google => _google(t.config, messages, offered, exec, nudge),
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
          'parameters': compactSchema(b.tool.inputSchema),
        },
      };

  static String _short(String s, int n) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= n ? one : '${one.substring(0, n)}…';
  }

  static String _describe(ToolBinding b) =>
      '${b.tool.description.isEmpty ? b.tool.name : _short(b.tool.description, 600)} (from ${b.serverName}${b.tool.readOnly ? '' : '; changes data, the user must approve'})';

  /// Same schema, with long property descriptions shortened and noise removed.
  static Object? compactSchema(Object? s) {
    if (s is List) return s.map(compactSchema).toList();
    if (s is! Map) return s;
    return {
      for (final e in s.entries)
        if (e.key != r'$schema' && e.key != 'title' && e.key != 'examples')
          e.key: e.key == 'description' && e.value is String ? _short(e.value as String, 200) : compactSchema(e.value),
    };
  }

  /// Context size for a request: small when possible (fast), bigger when needed.
  static int ctxFor(Object request, int maxCtx) {
    final est = jsonEncode(request).length ~/ 3 + 2048;
    for (final c in [8192, 16384, 32768, 65536]) {
      if (est <= c && c <= maxCtx) return c;
    }
    return maxCtx;
  }

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
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec, String? Function() nudge) async {
    final msgs = <Map<String, Object?>>[for (final m in messages) m.toJson()];
    for (var round = 0; round < maxRounds; round++) {
      final fns = tools.map(_fn).toList();
      final ctx = ctxFor([msgs, fns], t.maxCtx);
      Map<String, dynamic> r;
      try {
        r = await _post('${t.base}/api/chat', {}, {
          'model': t.model,
          'messages': msgs,
          if (fns.isNotEmpty) 'tools': fns,
          'stream': false,
          'keep_alive': -1,
          'think': ?(t.disableThinking ? false : null),
          'options': {'num_ctx': ctx, 'temperature': 0.4},
        });
      } on CloudError catch (e) {
        if (!e.message.contains('context')) rethrow;
        throw CloudError('This is more than the model can hold at once. Start a new chat, or use a bigger model or a cloud AI.');
      }
      final m = (r['message'] as Map).cast<String, dynamic>();
      final calls = (m['tool_calls'] as List?) ?? [];
      if (calls.isEmpty) {
        final n = nudge();
        if (n == null) return _stripThink((m['content'] as String?) ?? '');
        msgs.add({'role': 'assistant', 'content': m['content'] ?? ''});
        msgs.add({'role': 'user', 'content': n});
        continue;
      }
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
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec, String? Function() nudge) async {
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
      if (calls.isEmpty) {
        final n = nudge();
        if (n == null) return (m['content'] as String?) ?? '';
        msgs.add({'role': 'assistant', 'content': m['content'] ?? ''});
        msgs.add({'role': 'user', 'content': n});
        continue;
      }
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
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec, String? Function() nudge) async {
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
            for (final b in tools) {'name': b.fnName, 'description': _describe(b), 'input_schema': compactSchema(b.tool.inputSchema)}
          ],
      });
      final content = (r['content'] as List).cast<Map<String, dynamic>>();
      final uses = content.where((b) => b['type'] == 'tool_use').toList();
      if (r['stop_reason'] != 'tool_use' || uses.isEmpty) {
        final n = nudge();
        if (n == null) return content.where((b) => b['type'] == 'text').map((b) => b['text']).join().trim();
        msgs.add({'role': 'assistant', 'content': content});
        msgs.add({'role': 'user', 'content': n});
        continue;
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
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec, String? Function() nudge) async {
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
                for (final b in tools) {'name': b.fnName, 'description': _describe(b), 'parameters': geminiSchema(compactSchema(b.tool.inputSchema))}
              ]
            }
          ],
      });
      final content = ((r['candidates'] as List?)?.firstOrNull?['content'] as Map?)?.cast<String, dynamic>();
      final parts = ((content?['parts'] as List?) ?? []).cast<Map<String, dynamic>>();
      final calls = parts.where((p) => p['functionCall'] != null).toList();
      if (calls.isEmpty) {
        final n = nudge();
        if (n == null) return parts.map((p) => p['text'] ?? '').join().trim();
        if (content != null) contents.add(content);
        contents.add({
          'role': 'user',
          'parts': [
            {'text': n}
          ]
        });
        continue;
      }
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
