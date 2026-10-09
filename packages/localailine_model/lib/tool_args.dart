import 'dart:convert';

/// Checks and fixes a model's tool inputs before they reach the server, and
/// turns server errors into short messages the model (and you) can act on.
class ToolArgs {
  /// Returns cleaned inputs, or a problem to send back to the model instead
  /// of calling the server.
  static ({Map<String, dynamic> args, String? problem}) prepare(
    Map<String, dynamic> schema,
    Map<String, dynamic> args, {
    DateTime? now,
    String? Function(String entity)? lookupToolFor,
    bool Function(String key, String value)? looksWrongId,
    String? toolName,
  }) {
    final retry = toolName == null ? 'then try again' : 'then call $toolName again with it';
    final props = ((schema['properties'] as Map?) ?? {}).cast<String, dynamic>();
    final required = ((schema['required'] as List?) ?? []).cast<String>().toSet();
    final out = <String, dynamic>{};
    final problems = <String>[];

    for (final e in args.entries) {
      final spec = (props[e.key] as Map?)?.cast<String, dynamic>();
      var v = e.value;
      // Optional inputs sent as null/"" mean "not given".
      if (!required.contains(e.key) && (v == null || (v is String && v.trim().isEmpty))) continue;
      if (spec != null) {
        final (fixed, err) = _coerce(e.key, v, spec, now ?? DateTime.now());
        if (err != null) {
          problems.add(err);
          continue;
        }
        v = fixed;
      }
      // An id field given a name (spaces, or obviously not an id).
      if (_isIdKey(e.key) && v is String && (v.contains(' ') || v.length < 3 || (looksWrongId?.call(e.key, v) ?? false))) {
        final entity = _entityOf(e.key);
        final tool = lookupToolFor?.call(entity);
        problems.add('`${e.key}` must be a real $entity id from a tool result ("$v" was not seen in any result).'
            '${tool == null ? '' : ' Call $tool first to find the id, $retry.'}');
        continue;
      }
      out[e.key] = v;
    }
    for (final r in required) {
      if (!out.containsKey(r) && !problems.any((p) => p.contains('`$r`'))) {
        final d = (props[r] as Map?)?['description'];
        final tool = _isIdKey(r) ? lookupToolFor?.call(_entityOf(r)) : null;
        problems.add('Missing required input `$r`${d == null ? '' : ' ($d)'}.${tool == null ? '' : ' Use $tool to find it, $retry.'}');
      }
    }
    return (args: out, problem: problems.isEmpty ? null : 'The tool was not called because of its inputs: ${problems.join(' ')}');
  }

  static String entityOf(String k) => _entityOf(k);

  static bool _isIdKey(String k) => RegExp(r'(_id|Id)$').hasMatch(k) && k != 'id';
  static String _entityOf(String k) =>
      k.replaceAll(RegExp(r'(_id|Id)$'), '').replaceAll('_', ' ').replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}').trim();

  /// The non-null type(s) a schema allows (handles anyOf: [{type: x}, {type: null}]).
  static Set<String> _types(Map<String, dynamic> spec) {
    final t = spec['type'];
    final out = <String>{
      if (t is String) t,
      if (t is List) ...t.cast<String>(),
      for (final a in (spec['anyOf'] as List? ?? spec['oneOf'] as List? ?? const []))
        if (a is Map && a['type'] is String) a['type'] as String,
    }..remove('null');
    return out;
  }

  static List<Object?>? _enum(Map<String, dynamic> spec) =>
      (spec['enum'] as List?) ??
      (spec['anyOf'] as List?)?.whereType<Map>().map((a) => a['enum']).whereType<List>().firstOrNull;

  static (Object?, String?) _coerce(String key, Object? v, Map<String, dynamic> spec, DateTime now) {
    final types = _types(spec);
    final enums = _enum(spec);
    if (enums != null && v is String && !enums.contains(v)) {
      final hit = enums.where((x) => '$x'.toLowerCase() == v.toLowerCase()).firstOrNull;
      if (hit != null) return (hit, null);
      return (null, '`$key` must be one of: ${enums.join(', ')} (got "$v").');
    }
    if (types.contains('boolean') && v is String) {
      final s = v.toLowerCase().trim();
      if (['true', 'yes', '1', 'y'].contains(s)) return (true, null);
      if (['false', 'no', '0', 'n'].contains(s)) return (false, null);
    }
    if ((types.contains('integer') || types.contains('number')) && v is String && num.tryParse(v.trim()) != null) {
      final n = num.parse(v.trim());
      return (types.contains('integer') && !types.contains('number') ? n.toInt() : n, null);
    }
    if (types.contains('string') && types.length == 1 && (v is num || v is bool)) return ('$v', null);
    if (types.contains('array') && v is String) {
      return ([for (final p in v.split(',')) if (p.trim().isNotEmpty) p.trim()], null);
    }
    final isDate = key.toLowerCase().contains('date') || spec['format'] == 'date' || spec['format'] == 'date-time';
    if (isDate && v is String && !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v.trim())) {
      final d = naturalDate(v, now);
      if (d == null) return (null, '`$key` must be a date like ${_iso(now)} (got "$v").');
      return (_iso(d), null);
    }
    return (v, null);
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "today", "yesterday", "3 days ago", "last week", "this month", "last month"…
  /// For ranges, words meaning a period give its first day.
  static DateTime? naturalDate(String s, DateTime now) {
    final t = s.toLowerCase().trim();
    final today = DateTime(now.year, now.month, now.day);
    switch (t) {
      case 'today' || 'now':
        return today;
      case 'yesterday':
        return today.subtract(const Duration(days: 1));
      case 'tomorrow':
        return today.add(const Duration(days: 1));
      case 'this week':
        return today.subtract(Duration(days: today.weekday - 1));
      case 'last week':
        return today.subtract(Duration(days: today.weekday - 1 + 7));
      case 'this month':
        return DateTime(now.year, now.month);
      case 'last month':
        return DateTime(now.year, now.month - 1);
      case 'this year':
        return DateTime(now.year);
      case 'last year':
        return DateTime(now.year - 1);
    }
    final ago = RegExp(r'^(\d+)\s*(day|week|month)s?\s*ago$').firstMatch(t);
    if (ago != null) {
      final n = int.parse(ago.group(1)!);
      return switch (ago.group(2)) {
        'day' => today.subtract(Duration(days: n)),
        'week' => today.subtract(Duration(days: 7 * n)),
        _ => DateTime(now.year, now.month - n, now.day),
      };
    }
    return DateTime.tryParse(s.trim());
  }
}

/// Remembers ids seen in results so made-up ids (names, slugs) are caught.
class IdMemory {
  final seen = <String>{};
  static final _re = RegExp(r'"(?:id|_id|[a-z][A-Za-z]*Id)"\s*:\s*"([^"]{3,64})"');
  static final _hex24 = RegExp(r'^[0-9a-f]{24}$');
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  void learn(String result) {
    for (final m in _re.allMatches(result)) {
      seen.add(m.group(1)!);
    }
  }

  /// True when [v] should not be used as an id: when a lookup tool exists, an
  /// id must come from a result (or the user); otherwise compare shapes.
  bool looksWrong(String v, {required bool canLookUp}) {
    if (seen.contains(v)) return false;
    if (canLookUp) return true;
    if (seen.length >= 3) {
      if (seen.every(_hex24.hasMatch) && !_hex24.hasMatch(v)) return true;
      if (seen.every(_uuid.hasMatch) && !_uuid.hasMatch(v)) return true;
    }
    return false;
  }
}

/// Turns raw tool errors into a short message with what to do next.
class ToolErrors {
  /// Some servers report failures as plain text without isError.
  static bool looksLikeError(String text) {
    final t = text.trimLeft();
    return t.startsWith('Error executing tool') ||
        RegExp(r'^(Error|Exception|Traceback)\b').hasMatch(t) ||
        RegExp(r'\bHTTP [45]\d\d on\b').hasMatch(t);
  }

  static String friendly(String raw) {
    final text = raw.trim();
    var code = int.tryParse(RegExp(r'\bHTTP (\d{3})\b').firstMatch(text)?.group(1) ?? '');
    String? message;
    // A JSON body inside the error: take its message/detail/title.
    final j = RegExp(r'\{[\s\S]*\}').firstMatch(text)?.group(0);
    if (j != null) {
      try {
        final m = jsonDecode(j);
        if (m is Map) {
          message = (m['message'] ?? m['detail'] ?? m['title'] ?? m['error'])?.toString();
          final errs = m['errors'];
          if (errs is Map && errs.isNotEmpty) {
            message = [message, for (final e in errs.entries) '${e.key}: ${e.value is List ? (e.value as List).join(' ') : e.value}']
                .whereType<String>()
                .join('; ');
          }
          code ??= (m['status'] as num?)?.toInt();
        }
      } catch (_) {}
    }
    // Python/pydantic validation errors.
    final missing = RegExp(r'\n?\s*(\w+)\s*\n?\s*Field required').allMatches(text).map((m) => m.group(1)).toSet();
    if (missing.isNotEmpty) message = 'Missing required input: ${missing.join(', ')}';
    message ??= text
        .replaceFirst(RegExp(r'^Error executing tool \w+:\s*'), '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (message.length > 300) message = '${message.substring(0, 300)}…';

    final advice = switch (code) {
      400 || 422 => 'The inputs were not accepted. Fix them and try once more.',
      401 || 403 => 'Your account is not allowed to do this. Tell the user.',
      404 => 'Nothing was found with that id. Check the id with a list tool.',
      409 => 'This conflicts with existing data. Tell the user.',
      429 => 'The server is busy. Tell the user to try again shortly.',
      final c? when c >= 500 => 'The server could not handle this request (often a wrong id or value). Check the inputs; if they are right, tell the user the server had a problem.',
      _ => 'Fix the inputs and try once more, or tell the user what went wrong.',
    };
    return 'Tool error${code == null ? '' : ' ($code)'}: $message. $advice';
  }
}
