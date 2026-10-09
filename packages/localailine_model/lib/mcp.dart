import 'dart:convert';

/// A tool offered by an MCP server.
class McpTool {
  McpTool({required this.name, required this.description, required this.inputSchema, required this.readOnly, this.title, this.hint, this.autoApprove = false});

  /// The server's own readOnlyHint, if it gave one.
  final bool? hint;
  final String name, description;
  final String? title;
  final Map<String, dynamic> inputSchema;

  /// From the server's `readOnlyHint`. Anything else asks before running.
  final bool readOnly;

  /// Runs without asking (e.g. a customer placing an order in an app built here).
  /// Only kept for apps built in LocalAILine; see [McpManager].
  final bool autoApprove;

  McpTool withoutAutoApprove() => McpTool(name: name, description: description, inputSchema: inputSchema, readOnly: readOnly, title: title, hint: hint);

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'title': title,
        if (hint != null || autoApprove) 'annotations': {'readOnlyHint': ?hint, if (autoApprove) 'localailineAutoApprove': true},
      };

  static McpTool fromJson(Map<String, dynamic> j) {
    final description = (j['description'] as String?) ?? '';
    final hint = j['annotations']?['readOnlyHint'];
    return McpTool(
      name: j['name'] as String,
      title: j['title'] as String? ?? j['annotations']?['title'] as String?,
      description: description,
      inputSchema: (j['inputSchema'] as Map?)?.cast<String, dynamic>() ?? {'type': 'object', 'properties': {}},
      hint: hint is bool ? hint : null,
      readOnly: hint is bool ? hint : inferReadOnly(j['name'] as String, description),
      autoApprove: j['annotations']?['localailineAutoApprove'] == true,
    );
  }

  /// When a server doesn't say, guess from the description and name.
  /// Errs on the safe side: anything that might write asks first.
  static bool inferReadOnly(String name, String description) {
    final d = description.toLowerCase();
    if (RegExp(r'writes data|destructive|deletes?\b|creates?\b|updates?\b|modif').hasMatch(d.split('\n').first) ||
        d.contains('writes data')) {
      return false;
    }
    if (RegExp(r'\bread[- ]only\b').hasMatch(d)) return true;
    return RegExp(r'^(get|list|query|count|search|find|read|fetch|describe|show)_').hasMatch(name.toLowerCase());
  }
}

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
