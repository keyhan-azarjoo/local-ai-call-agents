import 'dart:convert';

/// Makes tool output fit a model's context without silently losing data.
///
/// JSON (one value, a list, or several values one after another) is cleaned
/// of empty fields and image links and written compactly. If it still doesn't
/// fit, whole items are dropped from the end and the model is told exactly how
/// many it is seeing.
class ToolResults {
  static ({String text, bool cut}) compact(String raw, int maxChars, {Map<String, Map<String, String>> lookups = const {}}) {
    _lookups = lookups;
    final values = _parseAll(raw.trim());
    if (values == null) return _plain(raw, maxChars);

    List<Object?> items;
    String? wrapperKey;
    Map<String, Object?>? wrapper;
    if (values.length == 1 && values.first is List) {
      items = values.first as List<Object?>;
    } else if (values.length == 1 && values.first is Map) {
      // {"items": [...], "total": 50} style: shrink the biggest list inside.
      final m = (values.first as Map).cast<String, Object?>();
      final listKey = m.entries.where((e) => e.value is List).fold<MapEntry<String, Object?>?>(
          null, (best, e) => best == null || (e.value as List).length > (best.value as List).length ? e : best);
      if (listKey == null) return _fit(jsonEncode(_clean(m)), maxChars);
      wrapperKey = listKey.key;
      wrapper = {for (final e in m.entries) if (e.key != wrapperKey) e.key: _clean(e.value)};
      items = listKey.value as List<Object?>;
    } else {
      items = values;
    }

    final cleaned = [for (final i in items) _clean(i)];
    var lines = [for (final i in cleaned) jsonEncode(i)];
    // Too big? Shorten details step by step so no item is lost:
    // nested detail → short notes; false flags dropped; ids dropped where names were added.
    int size() => lines.fold<int>(0, (a, l) => a + l.length + 1);
    if (size() > maxChars - 400) lines = [for (final i in cleaned) jsonEncode(_shallow(i, 0))];
    if (size() > maxChars - 400) lines = [for (final i in cleaned) jsonEncode(_lean(_shallow(i, 0)))];
    final head = wrapper == null ? '' : '${jsonEncode(wrapper)}\n';
    final total = lines.length;
    final buf = StringBuffer(head)..writeln('$total item${total == 1 ? '' : 's'}:');
    final totals = _totals(cleaned);
    if (totals.isNotEmpty) buf.writeln('Totals (exact, use these numbers): $totals');
    // (if items get cut, the count line above still tells the model the true total)
    var shown = 0;
    for (final l in lines) {
      if (buf.length + l.length + 1 > maxChars - 220) break;
      buf.writeln(l);
      shown++;
    }
    if (shown < total) {
      buf.write('[Note: the first $shown of $total items are shown above; ${total - shown} more did not fit. '
          'List the ones shown, then say ${total - shown} more exist.]');
      return (text: buf.toString(), cut: true);
    }
    return (text: buf.toString().trimRight(), cut: false);
  }

  static ({String text, bool cut}) _plain(String raw, int maxChars) => _fit(raw, maxChars);

  static ({String text, bool cut}) _fit(String s, int maxChars) => s.length <= maxChars
      ? (text: s, cut: false)
      : (
          text: '${s.substring(0, maxChars - 160)}\n[INCOMPLETE: output cut at ${maxChars - 160} of ${s.length} characters. Tell the user it is incomplete.]',
          cut: true
        );

  static Map<String, Map<String, String>> _lookups = const {};
  static final _idKey = RegExp(r'^([a-z][A-Za-z]*?)(Id|Ids)$');

  static final _noiseKey = RegExp(r'(picture|image|avatar|icon|thumbnail|logo)(url|uri|path)?$', caseSensitive: false);

  /// Drops nulls, empty strings/lists/maps and image links; keeps everything else.
  static Object? _clean(Object? v) {
    if (v is Map) {
      final out = <String, Object?>{};
      for (final e in v.entries) {
        final k = '${e.key}';
        if (_noiseKey.hasMatch(k)) continue;
        final c = _clean(e.value);
        if (c == null || (c is String && c.isEmpty) || (c is List && c.isEmpty) || (c is Map && c.isEmpty)) continue;
        out[k] = c;
        // groupIds: [...] → also groupNames: [...] when we looked them up.
        final m = _idKey.firstMatch(k);
        final names = m == null ? null : _lookups[m.group(1)!.toLowerCase()];
        if (names != null) {
          if (c is List) {
            out['${m!.group(1)}Names'] = [for (final id in c) names['$id'] ?? 'unknown ($id)'];
          } else {
            out['${m!.group(1)}Name'] = names['$c'] ?? 'unknown ($c)';
          }
        }
      }
      return out;
    }
    if (v is List) return [for (final i in v) _clean(i)];
    return v;
  }

  /// Exact counts for fields with a few repeated values (group, status…),
  /// so the model doesn't have to count.
  static String _totals(List<Object?> items) {
    final maps = items.whereType<Map>().toList();
    if (maps.length < 3) return '';
    final out = <String>[];
    final keys = maps.expand((m) => m.keys).toSet();
    for (final k in keys) {
      if (out.length >= 4) break;
      if (_idKey.hasMatch('$k') || k == 'id') continue;
      final counts = <String, int>{};
      var ok = true;
      for (final m in maps) {
        var v = m[k];
        if (v is List && v.length == 1) v = v.first;
        if (v is List || v is Map) {
          ok = false;
          break;
        }
        final key = v == null ? '(none)' : '$v';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      if (!ok || counts.length < 2 || counts.length > 8 || counts.length == maps.length) continue;
      final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      out.add('$k: ${sorted.map((e) => '${e.key} ${e.value}').join(', ')}');
    }
    return out.join('; ');
  }

  /// Drops false flags, and raw ids where a name was filled in.
  static Object? _lean(Object? v) {
    if (v is! Map) return v;
    final out = <String, Object?>{};
    for (final e in v.entries) {
      final k = '${e.key}';
      if (e.value == false) continue;
      final m = _idKey.firstMatch(k);
      if (m != null && (v.containsKey('${m.group(1)}Names') || v.containsKey('${m.group(1)}Name'))) continue;
      out[k] = e.value is Map ? _lean(e.value) : e.value;
    }
    return out;
  }

  /// Keeps the top two levels; deeper lists/objects become a short note.
  static Object? _shallow(Object? v, int depth) {
    if (v is Map) {
      if (depth >= 2) return '{${v.length} fields}';
      return {for (final e in v.entries) e.key: _shallow(e.value, depth + 1)};
    }
    if (v is List) {
      if (depth >= 2 || (v.isNotEmpty && v.first is Map && depth >= 1)) return '[${v.length} entries]';
      return [for (final i in v) _shallow(i, depth + 1)];
    }
    if (v is String && v.length > 300) return '${v.substring(0, 300)}…';
    return v;
  }

  /// Parses one JSON value, or several written back to back (as some MCP
  /// servers do, one content block per item). Returns null if it isn't JSON.
  static List<Object?>? _parseAll(String s) {
    if (s.isEmpty || !(s.startsWith('{') || s.startsWith('['))) return null;
    try {
      return [jsonDecode(s)];
    } catch (_) {}
    final out = <Object?>[];
    var depth = 0, start = -1;
    var inStr = false, esc = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{' || c == '[') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
        if (depth == 0 && start >= 0) {
          try {
            out.add(jsonDecode(s.substring(start, i + 1)));
          } catch (_) {
            return null;
          }
          start = -1;
        }
      } else if (depth == 0 && c.trim().isNotEmpty) {
        return null; // text between values: not pure JSON
      }
    }
    return out.isEmpty ? null : out;
  }

  /// id → display name, from a list result (for filling in names next to ids).
  static Map<String, String> idNames(String raw) {
    final values = _parseAll(raw.trim()) ?? [];
    final items = <Object?>[];
    for (final v in values) {
      if (v is List) {
        items.addAll(v);
      } else if (v is Map && v.values.any((x) => x is List)) {
        items.addAll(v.values.whereType<List>().expand((l) => l));
      } else {
        items.add(v);
      }
    }
    final out = <String, String>{};
    for (final i in items.whereType<Map>()) {
      final id = i['id'] ?? i['_id'];
      final full = '${i['firstName'] ?? ''} ${i['lastName'] ?? ''}'.trim();
      final name = i['name'] ?? i['title'] ?? i['displayName'] ?? (full.isEmpty ? null : full);
      if (id != null && name != null) out['$id'] = '$name';
    }
    return out;
  }

  /// Entity names referenced by id fields, e.g. "groupIds" → "group".
  static Set<String> referencedEntities(String raw) => {
        for (final m in RegExp(r'"([a-z][A-Za-z]*?)Ids?"\s*:').allMatches(raw))
          if (m.group(1)!.length > 2) m.group(1)!.toLowerCase()
      };
}
