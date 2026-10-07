import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'app_data.dart';
import 'app_spec.dart';
import 'app_styles.dart';
import 'app_web.dart';

/// Runs one user-built app on this computer: its website (customers at `/`,
/// the manager at `/manage`), a small JSON API, and two MCP endpoints so Ava can
/// use it in chats and on calls:
/// - `/mcp`: what customers may do (callers can use it without approval)
/// - `/mcp/manager`: the rest, for the owner (needs the manager PIN)
class AppServer {
  /// Every tool call from an assistant (tests and diagnostics): app, tool, arguments, answer.
  static void Function(String app, String tool, Map<String, dynamic> args, String result, bool error)? onToolCall;

  AppServer({required this.data, required this.pin, this.filesDir, this.onSpecChanged, this.readPicture});
  final AppData data;
  String pin;

  /// Where uploaded pictures are kept (null = uploads off).
  final String? filesDir;

  /// The manager changed the website (texts, pictures, style) on the manager page.
  final Future<void> Function(AppSpec spec)? onSpecChanged;

  /// Reads records for a table from a photo (with an AI that can see). Throws with a message.
  final Future<List<Map<String, dynamic>>> Function(String table, String base64)? readPicture;
  HttpServer? _http;
  bool paused = false;

  AppSpec get spec => data.spec;
  bool get running => _http != null;
  int? get port => _http?.port;

  Future<void> start(int port) async {
    if (_http != null) return;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http!.listen((req) => unawaited(_handle(req)));
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
  }

  bool _isManager(HttpRequest req) => pin.isNotEmpty && req.headers.value('x-key') == pin;

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (path == '/app.css') return _send(req, 200, appCss, 'text/css');
      if (path == '/app.js') return _send(req, 200, appJs, 'application/javascript');
      if (path.startsWith('/mcp')) return await _mcp(req, manager: path == '/mcp/manager');
      if (path.startsWith('/files/')) return await _file(req, path.substring(7));
      if (paused && !(_isManager(req) && path.startsWith('/api/'))) {
        // The manager still sees and handles what came in; customers see "paused".
        if (path.startsWith('/api/')) return _json(req, 503, {'error': 'This app is paused right now.'});
        return _send(req, 503, pausedHtml(spec), 'text/html');
      }
      if (path.startsWith('/api/')) return await _api(req, path.substring(5));
      if (path == '/' || path.startsWith('/p/') || path == '/manage') return _send(req, 200, appHtml(spec, manager: path == '/manage'), 'text/html');
      return _send(req, 404, 'Not found', 'text/plain');
    } on AppDataError catch (e) {
      return _json(req, 400, {'error': e.message});
    } catch (e) {
      return _json(req, 500, {'error': '$e'});
    }
  }

  Future<void> _send(HttpRequest req, int code, String body, String type) async {
    req.response
      ..statusCode = code
      ..headers.set('Content-Type', '$type; charset=utf-8')
      ..headers.set('Cache-Control', 'no-store')
      ..write(body);
    await req.response.close();
  }

  Future<void> _json(HttpRequest req, int code, Object? body) => _send(req, code, jsonEncode(body), 'application/json');

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final s = await utf8.decoder.bind(req).join();
    if (s.trim().isEmpty) return {};
    final j = jsonDecode(s);
    return j is Map ? j.cast<String, dynamic>() : {};
  }

  /// What a visitor may see of the description: no manager-only parts unless signed in.
  Map<String, Object?> publicSpec(bool manager) {
    final j = spec.toJson();
    return {
      ...j,
      'manager': manager,
      'tables': [
        for (final t in spec.tables)
          if (manager || t.access.see || t.access.add)
            {...t.toJson(), 'fields': [for (final f in t.fields) if (manager || !f.managerOnly) f.toJson()]},
      ],
      'pages': [for (final p in spec.pages) if (manager || !p.manager) p.toJson()],
    };
  }

  Future<void> _api(HttpRequest req, String rest) async {
    final manager = _isManager(req);
    if (rest == '_spec') return _json(req, 200, publicSpec(manager));
    if (rest == '_login' && req.method == 'POST') {
      final b = await _body(req);
      if ('${b['pin']}'.trim() == pin) return _json(req, 200, {'ok': true});
      await Future.delayed(const Duration(milliseconds: 600)); // slows down guessing
      return _json(req, 403, {'error': 'Wrong PIN.'});
    }
    if (rest == '_upload' && req.method == 'POST') return _upload(req, manager);
    if (rest.startsWith('_import/') && req.method == 'POST') {
      if (!manager) return _json(req, 403, {'error': 'Only the manager can do that.'});
      final t = spec.table(rest.substring(8));
      if (t == null || readPicture == null) return _json(req, 404, {'error': 'Not available.'});
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > 12 * 1024 * 1024) return _json(req, 413, {'error': 'The picture is too big.'});
      }
      try {
        return _json(req, 200, {'rows': await readPicture!(t.id, base64Encode(bytes))});
      } catch (e) {
        return _json(req, 400, {'error': '$e'});
      }
    }
    if (rest == '_site' && req.method == 'PUT') {
      if (!manager) return _json(req, 403, {'error': 'Only the manager can do that.'});
      return _saveSite(req);
    }
    if (rest.startsWith('_plan/')) {
      // Which tables (stylists, rooms…) are booked when on a day. Customers see no names.
      final t = spec.table(rest.substring(6));
      final b = t == null ? null : BookingShape.of(spec, t);
      if (b == null || (!manager && !t!.access.add)) return _json(req, 404, {'error': 'Not found'});
      final date = req.uri.queryParameters['date'] ?? DateTime.now().toIso8601String().substring(0, 10);
      return _json(req, 200, await data.dayPlan(b, date, manager: manager));
    }
    final parts = rest.split('/');
    if (parts.length < 2 || parts.first != 't') return _json(req, 404, {'error': 'Not found'});
    final t = spec.table(parts[1]);
    if (t == null) return _json(req, 404, {'error': 'No such table.'});
    final id = parts.length > 2 ? int.tryParse(parts[2]) : null;
    Future<void> deny() => _json(req, 403, {'error': 'Only the manager can do that.'});

    switch (req.method) {
      case 'GET':
        if (!manager && !t.access.see) return deny();
        if (id != null) {
          final r = await data.get(t.id, id, manager: manager);
          return r == null ? _json(req, 404, {'error': 'Not found'}) : _json(req, 200, r);
        }
        return _json(req, 200, await data.list(t.id, search: req.uri.queryParameters['q'], manager: manager));
      case 'POST':
        if (!manager && !t.access.add) return deny();
        return _json(req, 200, {'id': await data.add(t.id, await _body(req), manager: manager, via: manager ? 'manager' : 'website')});
      case 'PUT':
        if (!manager) return deny();
        if (t.single) return _json(req, 200, {'id': await data.setSingle(t.id, await _body(req))});
        if (id == null) return _json(req, 400, {'error': 'Which record?'});
        await data.update(t.id, id, await _body(req));
        return _json(req, 200, {'ok': true});
      case 'DELETE':
        if (!manager) return deny();
        if (id == null) return _json(req, 400, {'error': 'Which record?'});
        await data.delete(t.id, id);
        return _json(req, 200, {'ok': true});
    }
    return _json(req, 405, {'error': 'Not allowed'});
  }

  // ---------------- pictures ----------------

  static const _types = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif'};

  Future<void> _file(HttpRequest req, String name) async {
    final dir = filesDir;
    if (dir == null || !RegExp(r'^[a-z0-9]+\.(jpg|jpeg|png|webp|gif)$').hasMatch(name)) return _send(req, 404, 'Not found', 'text/plain');
    final f = File('$dir/$name');
    if (!f.existsSync()) return _send(req, 404, 'Not found', 'text/plain');
    req.response
      ..headers.set('Content-Type', _types[name.split('.').last]!)
      ..headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  /// Saves a picture (the page makes it small first). Customers may only upload
  /// where they can add records with a photo (e.g. a review).
  Future<void> _upload(HttpRequest req, bool manager) async {
    final dir = filesDir;
    if (dir == null) return _json(req, 400, {'error': 'Pictures are not available.'});
    final customersMay = spec.tables.any((t) => t.access.add && t.fields.any((f) => f.type == 'image' && !f.managerOnly));
    if (!manager && !customersMay) return _json(req, 403, {'error': 'Only the manager can upload pictures.'});
    final type = (req.headers.contentType?.mimeType ?? '').toLowerCase();
    final ext = _types.entries.where((e) => e.value == type).firstOrNull?.key;
    if (ext == null) return _json(req, 400, {'error': 'Use a JPG, PNG or WebP picture.'});
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > (manager ? 12 : 5) * 1024 * 1024) return _json(req, 413, {'error': 'The picture is too big.'});
    }
    Directory(dir).createSync(recursive: true);
    final r = Random.secure();
    final name = '${List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join()}.${ext == 'jpeg' ? 'jpg' : ext}';
    await File('$dir/$name').writeAsBytes(bytes);
    return _json(req, 200, {'url': '/files/$name'});
  }

  /// The manager's Website settings: name, details, style, colour and page texts.
  Future<void> _saveSite(HttpRequest req) async {
    final b = await _body(req);
    final site = Map<String, String>.of(spec.site);
    if (b['site'] is Map) {
      for (final k in AppSpec.siteKeys) {
        final v = (b['site'] as Map)[k];
        if (v == null) continue;
        final t = '$v'.trim();
        if (t.isEmpty) {
          site.remove(k);
        } else {
          site[k] = t.length > 1500 ? t.substring(0, 1500) : t;
        }
      }
    }
    if (!siteStyles.any((x) => x.id == site['style'])) site.remove('style');
    final theme = '${b['theme'] ?? spec.theme}'.trim();
    final edits = b['pages'] is Map ? (b['pages'] as Map) : const {};
    final pages = <PageSpec>[];
    for (final p in spec.pages) {
      final e = edits[p.id] is Map ? edits[p.id] as Map : const {};
      final blocks = e['blocks'] is Map ? e['blocks'] as Map : const {};
      final title = '${e['title'] ?? ''}'.trim();
      pages.add(p.copyWith(
        title: title.isEmpty ? null : title,
        blocks: [for (final (i, bl) in p.blocks.indexed) _editedBlock(bl, blocks['$i'])],
      ));
    }
    final name = '${b['name'] ?? ''}'.trim();
    final next = spec.copyWith(
      name: name.isEmpty ? null : (name.length > 80 ? name.substring(0, 80) : name),
      site: site,
      theme: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(theme) ? theme : '',
      pages: pages,
    );
    data.spec = next;
    await onSpecChanged?.call(next);
    return _json(req, 200, {'ok': true});
  }

  static Block _editedBlock(Block b, Object? edit) {
    if (edit is! Map || edit.isEmpty) return b;
    final d = Map<String, Object?>.of(b.data);
    final keys = switch (b.type) { 'hero' => const ['title', 'text', 'button', 'image'], 'text' => const ['text'], _ => const ['title'] };
    for (final k in keys) {
      if (!edit.containsKey(k)) continue;
      final v = '${edit[k] ?? ''}'.trim();
      if (v.isEmpty && !(b.type == 'text' && k == 'text')) {
        d.remove(k);
      } else {
        d[k] = v.length > 2000 ? v.substring(0, 2000) : v;
      }
    }
    if (b.type == 'hero' && (d['title'] ?? '').toString().isEmpty) return b;
    return Block(d);
  }

  // ---------------- MCP ----------------

  Future<void> _mcp(HttpRequest req, {required bool manager}) async {
    if (req.method != 'POST') return _json(req, 405, {'error': 'Use POST'});
    if (manager && !_isManager(req)) return _json(req, 401, {'error': 'The manager PIN is needed.'});
    final msg = await _body(req);
    final id = msg['id'];
    final method = msg['method'] as String? ?? '';
    req.response.headers.set('Mcp-Session-Id', 'app');
    if (id == null) {
      req.response.statusCode = 202;
      return req.response.close();
    }
    Object? result;
    Map<String, Object?>? error;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': (msg['params']?['protocolVersion'] as String?) ?? '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': manager ? '${spec.name} (manager)' : spec.name, 'version': '1'},
          'instructions': spec.summary,
        };
      case 'ping':
        result = {};
      case 'tools/list':
        result = {'tools': [for (final t in mcpTools(manager: manager)) t.toJson()]};
      case 'tools/call':
        final p = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};
        final args = (p['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
        try {
          if (paused) throw AppDataError('${spec.name} is paused right now.');
          final text = await callTool('${p['name']}', args, manager: manager);
          result = {'content': [{'type': 'text', 'text': text}]};
          onToolCall?.call(spec.name, '${p['name']}', args, text, false);
        } on AppDataError catch (e) {
          result = {'content': [{'type': 'text', 'text': e.message}], 'isError': true};
          onToolCall?.call(spec.name, '${p['name']}', args, e.message, true);
        }
      default:
        error = {'code': -32601, 'message': 'Unknown method $method'};
    }
    return _json(req, 200, {'jsonrpc': '2.0', 'id': id, 'result': ?result, 'error': ?error});
  }

  /// The tools each endpoint offers. Customers' tools and the manager's don't overlap,
  /// so the owner (who gets both) sees each tool once.
  List<AppTool> mcpTools({required bool manager}) {
    final out = <AppTool>[];
    final app = spec.name;
    for (final t in spec.tables) {
      final what = t.title.toLowerCase();
      final see = manager ? !t.access.see : t.access.see;
      final add = manager ? !t.access.add : t.access.add;
      final fields = [for (final f in t.fields) if (manager || !f.managerOnly) f];
      final about = t.purpose.isEmpty ? '' : ' ${t.purpose}';
      if (see) {
        if (t.single) {
          out.add(AppTool('get_${t.id}', 'Shows the $what of $app.$about', {}, const [], readOnly: true));
        } else {
          out.add(AppTool('list_${t.id}', 'Lists or searches the $what of $app.$about Fields: ${fields.map((f) => f.label).join(', ')}.',
              {'search': {'type': 'string', 'description': 'Words to look for (optional)'}}, const [], readOnly: true));
        }
      }
      final shape = BookingShape.of(spec, t);
      if (shape != null && !manager && t.access.add) {
        final what = shape.resources.title.toLowerCase();
        out.add(AppTool('check_${t.id}', 'For a NEW booking: shows which $what of $app are free at a date and time. Not for someone\'s existing booking (that is find_my_${t.id}).', {
          'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'time': {'type': 'string', 'description': 'HH:MM'},
          if (shape.guestsField != null) 'guests': {'type': 'integer', 'description': 'How many people'},
        }, const ['date', 'time'], readOnly: true));
      }
      final phoneF = t.fields.where((f) => f.type == 'phone').firstOrNull;
      if (!manager && t.access.add && !t.single && phoneF != null) {
        out.add(AppTool('find_my_${t.id}', 'Looks up the caller\'s EXISTING $what in $app by phone number — for "when is my booking?", "what time is my table?", "cancel/change my booking". Use it before saying anything about their booking.', {
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
          'name': {'type': 'string', 'description': 'Their name, if given'},
        }, const ['phone'], readOnly: true));
        out.add(AppTool('change_my_${t.id}', 'Changes one of the caller\'s own $what in $app (a new time or day, more people, other items…) instead of making a new one. Give only what changes. Only works for their phone number.', {
          'id': {'type': 'integer', 'description': 'Its id, from find_my_${t.id} (leave out if they have only one)'},
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
          for (final f in fields) if (f.type != 'phone' && !f.managerOnly) f.id: _schema(f),
        }, const ['phone'], auto: true));
        out.add(AppTool('cancel_my_${t.id}', 'Cancels one of the caller\'s own $what in $app, after they confirmed which one. Only works for their phone number.', {
          'id': {'type': 'integer', 'description': 'Its id, from find_my_${t.id} (leave out if they have only one)'},
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
        }, const ['phone'], auto: true));
      }
      if (add && !t.single) {
        out.add(AppTool('add_${t.id}', manager ? 'Adds a record to the $what of $app.$about' : 'Adds a new record to the $what of $app (e.g. a customer order or booking).$about',
            {for (final f in fields) f.id: _schema(f)}, [for (final f in fields) if (f.required && f.when == null) f.id], auto: !manager));
      }
      if (manager) {
        if (t.single) {
          out.add(AppTool('set_${t.id}', 'Changes the $what of $app. Give only the fields to change.', {for (final f in fields) f.id: _schema(f)}, const []));
        } else {
          out.add(AppTool('update_${t.id}', 'Changes a record in the $what of $app. Give its id and only the fields to change.',
              {'id': {'type': 'integer', 'description': 'Record id (from list_${t.id})'}, for (final f in fields) f.id: _schema(f)}, const ['id']));
          out.add(AppTool('delete_${t.id}', 'Deletes a record from the $what of $app.', {'id': {'type': 'integer', 'description': 'Record id (from list_${t.id})'}}, const ['id']));
        }
      }
    }
    return out;
  }

  Map<String, Object?> _schema(FieldSpec f) {
    final s = _schemaOf(f);
    final w = f.when;
    if (w == null) return s;
    final on = spec.tables.expand((t) => t.fields).where((x) => x.id == w.key).firstOrNull?.label ?? w.key;
    return {...s, 'description': '${s['description']} — only for $on ${w.value.join(' / ')}${f.required ? ' (then required)' : ''}'};
  }

  Map<String, Object?> _schemaOf(FieldSpec f) {
    final target = f.link == null ? null : spec.table(f.link!)?.title.toLowerCase();
    return switch (f.type) {
      'number' || 'money' => {'type': 'number', 'description': f.label},
      'yesno' => {'type': 'boolean', 'description': f.label},
      'choice' => {'type': 'string', 'enum': f.options, 'description': f.label},
      'date' => {'type': 'string', 'description': '${f.label} (YYYY-MM-DD)'},
      'time' => {'type': 'string', 'description': '${f.label} (HH:MM, 24-hour: 9am = 09:00, 7pm = 19:00, 9pm = 21:00)'},
      'datetime' => {'type': 'string', 'description': '${f.label} (YYYY-MM-DD HH:MM, 24-hour)'},
      'link' => {'type': 'string', 'description': '${f.label}: the name or id of one of the $target'},
      'links' when f.qty => {
          'type': 'array',
          'description': '${f.label}: items from the $target, each with a quantity',
          'items': {
            'type': 'object',
            'properties': {'item': {'type': 'string', 'description': 'Name or id'}, 'qty': {'type': 'integer'}},
            'required': ['item'],
          },
        },
      'links' => {'type': 'array', 'description': '${f.label}: names or ids of $target', 'items': {'type': 'string'}},
      _ => {'type': 'string', 'description': f.label},
    };
  }

  /// A customer's own bookings/orders: found and cancelled only with their phone number.
  Future<String> _mine(String name, Map<String, dynamic> args) async {
    final change = name.startsWith('change_my_');
    final cancel = name.startsWith('cancel_my_') || change;
    final t = spec.table(name.substring(change ? 10 : cancel ? 10 : 8))!;
    final phoneF = t.fields.firstWhere((f) => f.type == 'phone');
    final phone = '${args['phone'] ?? ''}';
    if (phone.replaceAll(RegExp(r'\D'), '').length < 6) throw AppDataError('Ask for their phone number first.');
    final what = t.title.toLowerCase();
    final shape = BookingShape.of(spec, t);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final mine = [
      for (final r in await data.list(t.id, manager: true))
        if (samePhone(r[phoneF.id], phone) && !(shape?.cancelled(r) ?? false) && (shape == null || '${r[shape.dateField.id] ?? ''}'.compareTo(today) >= 0)) r,
    ];
    if (!cancel) {
      if (mine.isEmpty) return 'No $what found for the phone number $phone. Tell the caller you can\'t find one under this number (they may have used another number).';
      final named = '${args['name'] ?? ''}'.trim().toLowerCase();
      final label = t.labelField;
      return 'Found ${mine.length} for $phone${named.isEmpty || mine.any((r) => '${r[label]}'.toLowerCase().contains(named.split(' ').first)) ? '' : ' (under a different name — check with the caller)'}:\n'
          '${await data.describe(t.id, [for (final r in mine) {for (final e in r.entries) if (e.key != 'created_at' && e.key != 'via') e.key: e.value}])}';
    }
    // Which one: the id given if it's theirs; else, when they have just one, that one.
    final id = (args['id'] as num?)?.toInt() ?? int.tryParse('${args['id'] ?? ''}');
    var r = id == null ? null : await data.get(t.id, id, manager: true);
    if (r != null && !samePhone(r[phoneF.id], phone)) {
      throw AppDataError('That $what is under a different phone number, so it can\'t be ${change ? 'changed' : 'cancelled'} from this number. Tell the caller to call from the number they booked with.');
    }
    if (r == null || !mine.any((m) => m['id'] == r!['id'])) {
      if (mine.isEmpty) throw AppDataError('No $what found for the phone number $phone, so there is nothing to ${change ? 'change' : 'cancel'}. Tell the caller.');
      if (mine.length > 1) {
        throw AppDataError('They have ${mine.length}: ask which one, then call again with its id.\n${await data.describe(t.id, mine)}');
      }
      r = mine.single;
    }
    final rid = r['id'] as int;
    if (change) {
      await data.change(t.id, rid, {for (final e in args.entries) if (e.key != 'id' && e.key != 'phone' && e.value != null && '${e.value}'.isNotEmpty) e.key: e.value});
      return 'Done. Changed (the old details are replaced):\n${await data.describe(t.id, [(await data.get(t.id, rid, manager: true))!])}';
    }
    final status = shape?.statusField ?? t.fields.where((f) => f.type == 'choice' && f.managerOnly).firstOrNull;
    final cancelled = status?.options.where((o) => RegExp(r'cancel', caseSensitive: false).hasMatch(o)).firstOrNull;
    if (status != null && cancelled != null) {
      await data.update(t.id, rid, {status.id: cancelled});
    } else {
      await data.delete(t.id, rid);
    }
    return 'Cancelled. ${await data.describe(t.id, [r])}';
  }

  static final _placeholder = RegExp(r'^(guest|customer|caller|client|unknown|n/?a|none|name|user|walk.?in|anonymous|patient|student|test|tbc|son|daughter|child|kid|boy|girl|wife|husband|partner|me|myself|mum|mom|dad|friend|\?+|-+)(\s*\d*)?$', caseSensitive: false);

  Future<String> callTool(String name, Map<String, dynamic> args, {required bool manager}) async {
    final tool = mcpTools(manager: manager).where((t) => t.name == name).firstOrNull;
    if (tool == null) throw AppDataError('Unknown tool $name.');
    if (RegExp(r'^(find|cancel|change)_my_').hasMatch(name)) return _mine(name, args);
    final verb = name.substring(0, name.indexOf('_'));
    final t = spec.table(name.substring(verb.length + 1))!;
    switch (verb) {
      case 'check':
        final b = BookingShape.of(spec, t)!;
        final date = parseDate('${args['date'] ?? ''}') ?? (throw AppDataError('Give the date as YYYY-MM-DD (today is ${withDay(DateTime.now().toIso8601String().substring(0, 10))}).'));
        final time = parseTime('${args['time'] ?? ''}') ?? (throw AppDataError('Give the time as HH:MM, 24-hour (7pm = 19:00).'));
        final guests = (args['guests'] as num?)?.toInt() ?? int.tryParse('${args['guests'] ?? ''}') ?? 0;
        final a = await data.availability(b, date, time, guests: guests);
        String show(Map<String, Object?> r) => '${r[b.resources.labelField] ?? r['id']}${b.seatsField != null ? ' (${r[b.seatsField!.id]} seats)' : ''}';
        final what = b.resources.title.toLowerCase();
        final on = withDay(date);
        return a.free.isEmpty
            ? 'Nothing is free at $time on $on${guests > 0 ? ' for $guests' : ''}. Offer another time.'
            : 'Free $what at $time on $on${guests > 0 ? ' for $guests' : ''}: ${a.free.map(show).join(', ')}. '
                '${a.taken.isEmpty ? '' : 'Booked: ${a.taken.map(show).join(', ')}. '}A booking lasts ${data.bookingMinutes} minutes. '
                'This only checked — NOTHING IS BOOKED YET. Once you have the caller\'s name and phone and they agree, call add_${t.id} to book '
                '(you may leave the ${b.resourceField.label.toLowerCase()} out: the best free one is given).';
      case 'list':
        final rows = await data.list(t.id, search: args['search'] as String?, manager: manager);
        return data.describe(t.id, rows.take(100).toList());
      case 'get':
        final r = await data.single(t.id, manager: manager);
        return r.isEmpty ? 'Not set yet.' : data.describe(t.id, [r]);
      case 'add':
        if (!manager) {
          // A made-up name ("Guest", "Caller") means the name was never asked.
          for (final f in t.fields.where((f) => f.type == 'text' && RegExp(r'name|student|patient', caseSensitive: false).hasMatch('${f.id} ${f.label}'))) {
            final v = '${args[f.id] ?? ''}'.trim();
            if (v.isNotEmpty && _placeholder.hasMatch(v)) throw AppDataError('Ask the caller for their ${f.label.toLowerCase().replaceFirst('your ', '')} first ("$v" is not a name), then save it.');
          }
        }
        if (!manager) {
          // Saved already in this call (the caller corrected something, or the AI saved twice): change that one.
          final shape = BookingShape.of(spec, t);
          final prev = await data.recentByPhone(t, '${args[t.fields.where((f) => f.type == 'phone').firstOrNull?.id] ?? ''}',
              date: shape == null ? null : parseDate('${args[shape.dateField.id] ?? ''}'), name: '${args[t.labelField] ?? ''}');
          if (prev != null) {
            await data.change(t.id, prev, args);
            return 'Done. Updated the one saved earlier in this call (not a second one):\n${await data.describe(t.id, [(await data.get(t.id, prev, manager: false))!])}';
          }
        }
        data.autoSwap = !manager;
        data.swapped = null;
        final int id;
        try {
          id = await data.add(t.id, args, manager: manager, via: 'phone');
        } finally {
          data.autoSwap = false;
        }
        if (data.swapped != null) return 'Done (${data.swapped} — tell the caller). Added to ${t.title.toLowerCase()} with id $id:\n${await data.describe(t.id, [(await data.get(t.id, id, manager: manager))!])}';
        return 'Done. Added to ${t.title.toLowerCase()} with id $id:\n${await data.describe(t.id, [(await data.get(t.id, id, manager: manager))!])}';
      case 'set':
        await data.setSingle(t.id, args);
        return 'Saved:\n${await data.describe(t.id, [await data.single(t.id, manager: true)])}';
      case 'update':
        final id = (args['id'] as num?)?.toInt() ?? (throw AppDataError('Give the record id.'));
        await data.update(t.id, id, Map.of(args)..remove('id'));
        return 'Saved:\n${await data.describe(t.id, [(await data.get(t.id, id, manager: true))!])}';
      case 'delete':
        final id = (args['id'] as num?)?.toInt() ?? (throw AppDataError('Give the record id.'));
        await data.delete(t.id, id);
        return 'Deleted record $id from ${t.title.toLowerCase()}.';
    }
    throw AppDataError('Unknown tool $name.');
  }
}

/// Same number, however it's written (07700 900124 = 07700 900124).
bool samePhone(Object? a, Object? b) {
  String d(Object? x) => '${x ?? ''}'.replaceAll(RegExp(r'\D'), '');
  final x = d(a), y = d(b);
  if (x.length < 6 || y.length < 6) return false;
  final n = x.length < y.length ? x.length : y.length;
  final k = n < 9 ? n : 9;
  return x.substring(x.length - k) == y.substring(y.length - k);
}

class AppTool {
  AppTool(this.name, this.description, this.properties, this.required, {this.readOnly = false, this.auto = false});
  final String name, description;
  final Map<String, Object?> properties;
  final List<String> required;
  final bool readOnly;

  /// Safe for customers: Ava may run it on a call without asking the owner.
  final bool auto;

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': {'type': 'object', 'properties': properties, if (required.isNotEmpty) 'required': required},
        'annotations': {'readOnlyHint': readOnly, if (auto) 'localailineAutoApprove': true},
      };
}
