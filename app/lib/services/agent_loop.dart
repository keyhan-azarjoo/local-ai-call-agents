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

/// Built-in tool: exact arithmetic, because small models add up badly.
final calculator = ToolBinding(
  serverId: -2,
  serverName: 'LocalAILine',
  fnName: 'calculate',
  tool: McpTool(
    name: 'calculate',
    readOnly: true,
    description: 'Exact arithmetic for prices and totals. Example: "2*16.00 + 3.95". Use it for every sum.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'expression': {'type': 'string', 'description': 'Numbers with + - * / and brackets'}
      },
      'required': ['expression'],
    },
  ),
);

/// Built-in: a visible plan (like Claude's task list). The app shows it live
/// and keeps the loop going until every step is done.
final planTool = ToolBinding(
  serverId: -3,
  serverName: 'LocalAILine',
  fnName: 'update_plan',
  tool: McpTool(
    name: 'update_plan',
    readOnly: true,
    description: 'For requests with several steps: write or update your plan. Give every step with status todo, doing or done. '
        'Call it first, then mark steps done as you go.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'steps': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'step': {'type': 'string'},
              'status': {'type': 'string', 'enum': ['todo', 'doing', 'done']},
            },
            'required': ['step', 'status'],
          },
        },
      },
      'required': ['steps'],
    },
  ),
);

/// Built-in: short-lived helper agents for independent parts of a task.
/// Each gets a clean context and only the tools it needs, runs in parallel,
/// reports back, and is discarded.
final delegateTool = ToolBinding(
  serverId: -4,
  serverName: 'LocalAILine',
  fnName: 'delegate',
  tool: McpTool(
    name: 'delegate',
    readOnly: true,
    description: 'Hand independent parts of the task to helper agents that work in parallel and report back. '
        'Use for 2–4 separate lookups or jobs (e.g. "count parts for team A" and "count parts for team B").',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tasks': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'instructions': {'type': 'string', 'description': 'Everything the helper needs to know to do it alone'},
            },
            'required': ['title', 'instructions'],
          },
        },
      },
      'required': ['tasks'],
    },
  ),
);

/// Small, safe arithmetic evaluator (no variables, no functions).
class Calc {
  static double? eval(String input) {
    final s = input.replaceAll(RegExp(r'[£\$€,\s]'), '').replaceAll('x', '*').replaceAll('×', '*');
    if (s.isEmpty || RegExp(r'[^0-9.+\-*/()]').hasMatch(s)) return null;
    var i = 0;
    double? expr() {
      double? term() {
        double? factor() {
          if (i < s.length && (s[i] == '+' || s[i] == '-')) {
            final neg = s[i] == '-';
            i++;
            final f = factor();
            return f == null ? null : (neg ? -f : f);
          }
          if (i < s.length && s[i] == '(') {
            i++;
            final v = expr();
            if (i >= s.length || s[i] != ')') return null;
            i++;
            return v;
          }
          final m = RegExp(r'^\d+(\.\d+)?|^\.\d+').firstMatch(s.substring(i));
          if (m == null) return null;
          i += m.group(0)!.length;
          return double.parse(m.group(0)!);
        }

        var v = factor();
        while (v != null && i < s.length && (s[i] == '*' || s[i] == '/')) {
          final op = s[i++];
          final r = factor();
          if (r == null || (op == '/' && r == 0)) return null;
          v = op == '*' ? v * r : v / r;
        }
        return v;
      }

      var v = term();
      while (v != null && i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i++];
        final r = term();
        if (r == null) return null;
        v = op == '+' ? v + r : v - r;
      }
      return v;
    }

    final v = expr();
    return i == s.length ? v : null;
  }

  static String format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// Exact order totals. The app numbers every price line from the documents;
/// the model only says which lines and how many (easy for it); the app reads
/// the prices and adds them up (which small models get wrong).
class OrderQuote {
  static final _orderish = RegExp(
      r"\b(order|get|have|want|like|take|i.ll|i.d|add|buy|deliver|delivery|collect|collection|one|two|three|four|five|six|a couple|\d+)\b",
      caseSensitive: false);
  static final _price = RegExp(r'[£\$€]\s?(\d+(?:\.[\s   ]?\d{1,2})?)');
  static final _postcode = RegExp(r'\b([A-Z]{1,2}\d{1,2}[A-Z]?)(?:\s*\d[A-Z]{2})?\b');

  static bool worthChecking(String question) => _orderish.hasMatch(question);

  /// First price on a line ("Fish & chips … £16.00 …" → 16.0).
  static double? priceOf(String line) => double.tryParse((_price.firstMatch(line)?.group(1) ?? '').replaceAll(RegExp(r'\s'), ''));

  static Future<String?> quote(http.Client c, LocalTarget t, List<ChatMessage> conversation, List<String> priceLines) async {
    if (priceLines.isEmpty) return null;
    final numbered = [for (var i = 0; i < priceLines.length; i++) '${i + 1}. ${priceLines[i]}'].join('\n');
    final talk = conversation
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .map((m) => '${m.role == 'user' ? 'Customer' : 'Assistant'}: ${m.content.contains('\n\nQuestion: ') ? m.content.substring(m.content.lastIndexOf('\n\nQuestion: ') + 12) : m.content}')
        .join('\n');
    final r = await c
        .post(Uri.parse('${t.base}/api/chat'),
            body: jsonEncode({
              'model': t.model,
              'stream': false,
              'keep_alive': -1,
              'think': ?(t.disableThinking ? false : null),
              'options': {'num_ctx': t.maxCtx < 16384 ? t.maxCtx : 16384, 'temperature': 0},
              'format': {
                'type': 'object',
                'properties': {
                  'is_order': {'type': 'boolean'},
                  'lines': {
                    'type': 'array',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'line': {'type': 'integer'},
                        'quantity': {'type': 'number'},
                      },
                      'required': ['line', 'quantity'],
                    },
                  },
                },
                'required': ['is_order', 'lines'],
              },
              'messages': [
                {
                  'role': 'system',
                  'content': 'Match what the customer is ordering to the numbered price list. For each thing they order, give the line '
                      'number and quantity. Include a delivery or other fee line only if it applies to them (for example their postcode is '
                      'in that delivery zone). If they are not ordering, set is_order to false and lines to [].'
                },
                {'role': 'user', 'content': 'Price list:\n$numbered\n\nConversation:\n$talk'},
              ],
            }))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) return null;
    final j = jsonDecode((jsonDecode(r.body) as Map)['message']['content'] as String) as Map<String, dynamic>;
    if (j['is_order'] != true) return null;
    final picked = (j['lines'] as List? ?? []).cast<Map>().toList();
    // Delivery: add the zone line that names the caller's postcode area, if the model missed it.
    final said = conversation.where((m) => m.role == 'user').map((m) => m.content).join(' ');
    if (RegExp(r'deliver', caseSensitive: false).hasMatch(said)) {
      for (final pc in _postcode.allMatches(said.toUpperCase()).map((m) => m.group(1)!)) {
        final i = priceLines.indexWhere((l) => RegExp('\\b$pc\\b').hasMatch(l.toUpperCase()) && RegExp(r'zone|deliver', caseSensitive: false).hasMatch(l));
        if (i >= 0 && !picked.any((p) => p['line'] == i + 1)) picked.add({'line': i + 1, 'quantity': 1});
      }
    }
    var total = 0.0;
    final parts = <String>[];
    for (final l in picked) {
      final n = (l['line'] as num?)?.toInt() ?? 0;
      final q = (l['quantity'] as num?)?.toDouble() ?? 0;
      if (n < 1 || n > priceLines.length || q <= 0) continue;
      final line = priceLines[n - 1];
      final p = priceOf(line);
      if (p == null) continue;
      final name = line.substring(0, _price.firstMatch(line)!.start).trim();
      total += q * p;
      parts.add('${Calc.format(q)} × $name (£${p.toStringAsFixed(2)}) = £${(q * p).toStringAsFixed(2)}');
    }
    if (parts.isEmpty) return null;
    return 'Exact order total worked out by the app (use these numbers, do not recalculate): ${parts.join('; ')}. TOTAL £${total.toStringAsFixed(2)}.';
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

  /// Same word allowing one typo, or one word inside the other ("elist" ~ "list").
  static bool near(String a, String b) {
    if (a.length < 4 || b.length < 4) return false;
    if (a.contains(b) || b.contains(a)) return (a.length - b.length).abs() <= 2;
    if ((a.length - b.length).abs() > 1) return false;
    // Levenshtein distance ≤ 1.
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }

  static double score(Set<String> q, Set<String> verbs, ToolBinding b) {
    final name = words(b.tool.name.replaceAll('_', ' '), keepCommon: true);
    final title = words(b.tool.title ?? '');
    final desc = words(b.tool.description.length > 300 ? b.tool.description.substring(0, 300) : b.tool.description);
    final server = words(b.serverName);
    var sc = 0.0;
    for (final w in q) {
      if (name.contains(w)) {
        sc += 4;
      } else if (name.any((t) => near(w, t))) {
        sc += 3; // typo or glued word ("eusers" → "users")
      }
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
      if (all.any((w) => w == 'list' || near(w, 'list')) || all.contains('show') || all.contains('all')) ...['list', 'query'],
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
  http.Client get client => _c;

  static const maxRounds = 12;

  /// Plans and helper agents only for clearly multi-step requests (keeps the prompt short).
  static bool looksMultiStep(String q) =>
      q.length > 70 && RegExp(r'\b(and then|each|every|report|summar|compare|plan|step|for all|both)\b', caseSensitive: false).hasMatch(q);

  /// Added to the system prompt whenever tools are offered.
  static const toolRules = 'Tool rules: for a specific fact, the reference notes (data snapshots a few minutes old) are enough — answer from them. '
      'For a full list or a count, use a COMPLETE list in the notes if there is one; otherwise call the list or count tool. '
      'Never say you have no access before trying the tools. '
      'Never guess names, ids or numbers; reuse ids from results. '
      'Show the data you got; if a note says items are missing, say so. Use the Totals line for counts and calculate for sums. '
      'Lists: one short line per item ("1. Name — Group"), no sub-bullets or ids unless asked. '
      'Write money as £21.50 and dates as YYYY-MM-DD. If a tool fails, fix the input and retry once.';

  Future<String> run({
    required ModelTarget target,
    required List<ChatMessage> messages,
    required List<ToolBinding> tools,
    required Approver approve,
    required ToolRunner runTool,
    void Function(ToolEvent)? onEvent,
    void Function(String textSoFar)? onText,
    int depth = 0,
    Set<String> knownIds = const {},
    List<ToolBinding> preferred = const [],
    List<String>? sticky,
    bool warmOnly = false,
    void Function(ToolBinding)? onToolStart,
    bool builtins = true,
  }) async {
    final byName = {for (final t in tools) t.fnName: t};

    // Only the most relevant tools are offered; find_tools reaches the rest.
    final limit = target is LocalTarget ? 6 : 40;
    final resultLimit = switch (target) {
      LocalTarget t => t.maxCtx >= 16384 ? 14000 : 7000,
      CloudTarget _ => 40000,
    };
    {
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
    String q(String c) => c.contains('\n\nQuestion: ') ? c.substring(c.lastIndexOf('\n\nQuestion: ') + 12) : c;
    final lastUser = q(messages.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage('user', '')).content);
    final recent = messages.where((m) => m.role == 'user').toList().reversed.take(3).map((m) => q(m.content)).join(' ');
    // Tools matched by meaning (embeddings) first, then by words.
    final active = <ToolBinding>[...preferred.where(tools.contains).take(limit ~/ 2)];
    for (final t in ToolSelector.rank(lastUser, tools, limit)) {
      if (active.length >= limit) break;
      if (!active.contains(t)) active.add(t);
    }
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
    final finder = tools.length > 6
        ? ToolBinding(
            serverId: -1,
            serverName: 'LocalAILine',
            fnName: 'find_tools',
            tool: McpTool(
              name: 'find_tools',
              readOnly: true,
              description: 'Find more of the user’s tools (${tools.length} in ${tools.map((t) => t.serverName).toSet().join(', ')}) by keywords.',
              inputSchema: {
                'type': 'object',
                'properties': {
                  'query': {'type': 'string'}
                },
                'required': ['query'],
              },
            ),
          )
        : null;
    // Order matters for speed: the model keeps what it has read, so stable
    // things go first (built-ins, then tools already used in this chat), new
    // tools are appended, and the occasional plan/helper tools come last.
    final mcpOffered = <ToolBinding>[
      if (sticky != null)
        for (final name in sticky)
          if (byName[name] != null) byName[name]!,
    ];
    for (final t in active) {
      if (!mcpOffered.contains(t)) mcpOffered.add(t);
    }
    if (sticky != null) {
      sticky
        ..clear()
        ..addAll(mcpOffered.take(12).map((t) => t.fnName));
    }
    final offered = <ToolBinding>[
      if (builtins) calculator,
      ?finder,
      ...mcpOffered.take(12),
      if (tools.isNotEmpty && depth == 0 && looksMultiStep(lastUser)) ...[planTool, delegateTool],
    ];
    var plan = <Map<String, dynamic>>[];
    var planNudges = 0;
    final idCache = <String, Map<String, String>>{};
    final ids = IdMemory()..seen.addAll(knownIds);
    final recentResults = <String>[]; // shared with helper agents
    String? pendingRetry; // a tool refused for bad inputs, not yet retried
    var nudged = false;
    String? nudge() {
      if (pendingRetry != null && !nudged) {
        nudged = true;
        return 'You now have what you need. Call $pendingRetry again with the correct id or inputs, then answer my question.';
      }
      // Loop until the goal: finish every step of the plan.
      final open = plan.where((x) => x['status'] != 'done').map((x) => x['step']).toList();
      if (open.isNotEmpty && planNudges < 3) {
        planNudges++;
        return 'Your plan still has open steps: ${open.join('; ')}. Continue with them now, mark them done with update_plan, then give the final answer.';
      }
      return null;
    }
    for (final m in messages) {
      ids.learn(m.content);
    }

    Future<(String, bool)> exec(String name, Map<String, dynamic> args) async {
      if (name == calculator.fnName) {
        final expr = '${args['expression'] ?? ''}';
        final v = Calc.eval(expr);
        onEvent?.call(ToolEvent(calculator, args, result: v == null ? 'Could not calculate' : Calc.format(v), ok: v != null));
        return (v == null ? 'Could not calculate "$expr". Use numbers and + - * / ( ) only.' : '$expr = ${Calc.format(v)}', v == null);
      }
      if (name == planTool.fnName) {
        plan = [for (final x in (args['steps'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
        onEvent?.call(ToolEvent(planTool, {'steps': plan}, result: 'Plan updated', ok: true));
        final open = plan.where((x) => x['status'] != 'done').map((x) => x['step']).toList();
        return (open.isEmpty ? 'Plan complete.' : 'Plan saved. Next: ${open.first}', false);
      }
      if (name == delegateTool.fnName) {
        final tasks = [
          for (final x in (args['tasks'] as List? ?? []).take(4))
            () {
              final m = (x is Map ? x : {'instructions': '$x'}).cast<String, dynamic>();
              final instr = '${m['instructions'] ?? m['task'] ?? m['description'] ?? m['title'] ?? ''}';
              final words = instr.split(RegExp(r'\s+'));
              m['instructions'] = instr;
              m['title'] = '${m['title'] ?? m['name'] ?? (words.length > 7 ? '${words.take(7).join(' ')}…' : instr)}';
              return m;
            }()
        ];
        final shared = recentResults.isEmpty
            ? ''
            : '\n\nWhat the main agent already found (use these ids and facts):\n${recentResults.reversed.take(3).join('\n\n')}';
        final results = await Future.wait([
          for (final t in tasks)
            () async {
              final sw = Stopwatch()..start();
              onEvent?.call(ToolEvent(delegateTool, {'agent': t['title'], 'state': 'working'}, result: '', ok: true));
              String out;
              try {
                out = await run(
                  target: target,
                  depth: depth + 1,
                  messages: [
                    ChatMessage('system',
                        'You are a helper agent. Do only this task, using tools where needed, then report the result in a few short lines with exact numbers and names.'),
                    ChatMessage('user', '${t['instructions']}$shared'),
                  ],
                  knownIds: ids.seen,
                  tools: tools,
                  approve: approve,
                  runTool: runTool,
                  onEvent: (e) => onEvent?.call(ToolEvent(e.binding, {...e.args, '_agent': t['title']}, result: e.result, ok: e.ok, denied: e.denied)),
                );
              } on Cancelled {
                rethrow;
              } catch (e) {
                out = 'Failed: $e';
              }
              onEvent?.call(ToolEvent(delegateTool, {'agent': t['title'], 'state': 'done', 'ms': sw.elapsedMilliseconds}, result: out, ok: !out.startsWith('Failed')));
              return '### ${t['title']}\n$out';
            }(),
        ]);
        return ('Helper agents finished:\n\n${results.join('\n\n')}', false);
      }
      if (name == 'find_tools') {
        final found = ToolSelector.rank('${args['query'] ?? ''}', tools, 8);
        for (final f in found) {
          if (!offered.contains(f)) offered.insert(offered.contains(planTool) ? offered.indexOf(planTool) : offered.length, f);
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
      if (!offered.contains(b)) offered.insert(offered.contains(planTool) ? offered.indexOf(planTool) : offered.length, b);
      // Check the model's inputs first; don't send the server something it will reject.
      bool hasLookup(String entity) => ToolSelector.rank('list $entity', tools.where((t) => t.tool.readOnly).toList(), 1).isNotEmpty;
      final prepared = ToolArgs.prepare(b.tool.inputSchema, args,
          toolName: b.fnName,
          looksWrongId: (k, v) => ids.looksWrong(v, canLookUp: hasLookup(ToolArgs.entityOf(k))), lookupToolFor: (entity) {
        final t = ToolSelector.rank('list $entity', tools.where((t) => t.tool.readOnly).toList(), 1).firstOrNull;
        if (t != null && !offered.contains(t)) offered.insert(offered.contains(planTool) ? offered.indexOf(planTool) : offered.length, t);
        return t?.fnName;
      });
      if (prepared.problem != null) {
        pendingRetry = b.fnName;
        onEvent?.call(ToolEvent(b, args, result: prepared.problem!, ok: false));
        return (prepared.problem!, true);
      }
      if (pendingRetry == b.fnName) pendingRetry = null;
      args = prepared.args;
      onToolStart?.call(b);
      final ev = ToolEvent(b, args);
      if (!b.tool.readOnly && !b.tool.autoApprove && !await approve(b, args)) {
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
        if (!failed) {
          ids.learn(r.text);
          recentResults.add('${b.tool.name}: ${ToolResults.compact(r.text, 1500).text}');
        }
      } on Cancelled {
        rethrow;
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

    if (warmOnly) {
      if (target is LocalTarget) {
        final fns = offered.map(_fn).toList();
        final msgs = [for (final m in messages) m.toJson()];
        final baseCtx = target.maxCtx < 16384 ? target.maxCtx : 16384;
        final need = ctxFor([msgs, fns], target.maxCtx);
        try {
          await _post('${target.base}/api/chat', {}, {
            'model': target.model,
            'messages': msgs,
            if (fns.isNotEmpty) 'tools': fns,
            'stream': false,
            'keep_alive': -1,
            'think': ?(target.disableThinking ? false : null),
            'options': {'num_ctx': need > baseCtx ? need : baseCtx, 'num_predict': 0},
          });
        } catch (_) {}
      }
      return '';
    }
    return switch (target) {
      LocalTarget t => _ollama(t, messages, offered, exec, nudge, onText),
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
      '${b.tool.description.isEmpty ? b.tool.name : _short(b.tool.description, 160)} (from ${b.serverName}${b.tool.readOnly || b.tool.autoApprove ? '' : '; changes data, the user must approve'})';

  /// Same schema, with long property descriptions shortened and noise removed.
  static Object? compactSchema(Object? s) {
    if (s is List) return s.map(compactSchema).toList();
    if (s is! Map) return s;
    return {
      for (final e in s.entries)
        if (e.key != r'$schema' && e.key != 'title' && e.key != 'examples')
          e.key: e.key == 'description' && e.value is String ? _short(e.value as String, 80) : compactSchema(e.value),
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
      Future<(String, bool)> Function(String, Map<String, dynamic>) exec, String? Function() nudge,
      void Function(String)? onText) async {
    final msgs = <Map<String, Object?>>[for (final m in messages) m.toJson()];
    // One context size for the whole question: changing it makes Ollama reload
    // the model and re-read everything (seconds each time).
    final baseCtx = t.maxCtx < 16384 ? t.maxCtx : 16384;
    var brokenCalls = 0;
    for (var round = 0; round < maxRounds; round++) {
      final fns = tools.map(_fn).toList();
      final need = ctxFor([msgs, fns], t.maxCtx);
      final ctx = need > baseCtx ? need : baseCtx;
      Map<String, dynamic> m;
      try {
        m = await _ollamaStream(t, {
          'model': t.model,
          'messages': msgs,
          if (fns.isNotEmpty) 'tools': fns,
          'stream': true,
          'keep_alive': -1,
          'think': ?(t.disableThinking ? false : null),
          // A cap, so a model stuck repeating itself stops in seconds instead of minutes.
          'options': {'num_ctx': ctx, 'temperature': 0.4, 'num_predict': 1500},
        }, onText);
      } on CloudError catch (e) {
        // A tool call the model never finished (it got stuck repeating): ask once more, simply.
        final broken = RegExp(r'invalid tool call arguments for "([^"]+)"').firstMatch(e.message);
        if (broken != null && brokenCalls++ < 2) {
          msgs.add({'role': 'user', 'content': 'Your call to ${broken[1]} was cut off. Call it again now with short, plain values — only the fields you know, no long text.'});
          continue;
        }
        if (!e.message.contains('context')) rethrow;
        throw CloudError('This is more than the model can hold at once. Start a new chat, or use a bigger model or a cloud AI.');
      }
      final calls = (m['tool_calls'] as List?) ?? [];
      if (calls.isNotEmpty) onText?.call(''); // text before a tool call isn't the answer
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
    // Out of rounds: answer from what was found instead of giving up.
    msgs.add({
      'role': 'user',
      'content': 'Stop using tools now. Give the best answer you can from the results above, '
          'and say briefly what you could not find.'
    });
    final last = await _ollamaStream(t, {
      'model': t.model,
      'messages': msgs,
      'stream': true,
      'keep_alive': -1,
      'think': ?(t.disableThinking ? false : null),
      'options': {'num_ctx': baseCtx, 'temperature': 0.4, 'num_predict': 1500},
    }, onText);
    return _stripThink((last['content'] as String?) ?? '');
  }

  /// Streams one Ollama turn: shows the answer as it is written, and collects
  /// any tool calls. Returns the full assistant message.
  Future<Map<String, dynamic>> _ollamaStream(LocalTarget t, Map<String, Object?> body, void Function(String)? onText) async {
    final req = http.Request('POST', Uri.parse('${t.base}/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final res = await _c.send(req).timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      final b = await res.stream.bytesToString();
      var detail = b;
      try {
        detail = (jsonDecode(b)['error'] ?? b).toString();
      } catch (_) {}
      throw CloudError('Model error ${res.statusCode}: ${detail.length > 300 ? detail.substring(0, 300) : detail}');
    }
    final text = StringBuffer();
    final calls = <Object?>[];
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      if (j['error'] != null) throw CloudError('Model error: ${j['error']}');
      final msg = (j['message'] as Map?)?.cast<String, dynamic>();
      if (msg == null) continue;
      calls.addAll((msg['tool_calls'] as List?) ?? const []);
      final piece = msg['content'] as String? ?? '';
      if (piece.isNotEmpty) {
        text.write(piece);
        if (calls.isEmpty) onText?.call(_stripThink(text.toString()));
      }
    }
    return {'role': 'assistant', 'content': text.toString(), if (calls.isNotEmpty) 'tool_calls': calls};
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

/// Thrown (from a tool runner or text callback) to stop an answer nobody is waiting for any more.
class Cancelled implements Exception {
  const Cancelled();
}
