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

  AppServer({required this.data, required this.pin, this.toolKey = '', this.filesDir, this.onSpecChanged, this.readPicture});
  final AppData data;
  String pin;

  /// The secret only this computer's assistant holds: the tools (/mcp) answer no one else. Without
  /// it anyone on the same Wi-Fi could skip the assistant and look up or cancel any booking.
  final String toolKey;

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

  bool _isManager(HttpRequest req) {
    final key = req.headers.value('x-key');
    if (pin.isEmpty || key == null || key.isEmpty) return false;
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    if (_lockedOut(ip)) return false;
    if (sameSecret(key, pin)) return true;
    _failed(ip);
    return false;
  }

  // Guessing the PIN: after 5 wrong tries from one address it is locked out for 15 minutes, and
  // after 30 wrong tries in an hour from anywhere, every address is (a 6-digit PIN has a million
  // values, so unlimited tries would find it in minutes).
  final _fails = <String, List<DateTime>>{};
  void _failed(String ip) {
    final now = DateTime.now();
    (_fails[ip] ??= []).add(now);
    if (ip != '127.0.0.1' && ip != '::1') (_fails['*'] ??= []).add(now);
  }

  bool _lockedOut(String ip) {
    final now = DateTime.now();
    for (final l in _fails.values) {
      l.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    }
    final mine = (_fails[ip] ?? const []).where((t) => now.difference(t) < const Duration(minutes: 15)).length;
    // (This computer only counts its own tries: someone else guessing can't lock the owner out here.)
    final local = ip == '127.0.0.1' || ip == '::1';
    return mine >= 5 || (!local && (_fails['*']?.length ?? 0) >= 30);
  }

  /// Only this computer may use the tools, and only with the key (constant-time compare).
  bool _isAssistant(HttpRequest req) =>
      (req.connectionInfo?.remoteAddress.isLoopback ?? false) && toolKey.isNotEmpty && sameSecret(req.headers.value('x-tool-key') ?? '', toolKey);

  /// A web page elsewhere can't use this site behind the visitor's back: writes need the site's own
  /// header (other sites can't send it without asking first), and the address must be this
  /// computer's (not a look-alike name pointed here).
  bool _trusted(HttpRequest req) {
    final host = (req.headers.host ?? '').toLowerCase();
    final okHost = host.isEmpty || host == 'localhost' || host.endsWith('.local') || InternetAddress.tryParse(host) != null;
    if (!okHost) return false;
    if (req.method == 'GET' || req.method == 'HEAD') return true;
    return req.headers.value('x-key') != null || req.headers.value('x-tool-key') != null;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (path == '/app.css') return _send(req, 200, appCss, 'text/css');
      if (path == '/app.js') return _send(req, 200, appJs, 'application/javascript');
      if (!_trusted(req)) return _json(req, 403, {'error': 'Not allowed.'});
      if (path.startsWith('/mcp')) {
        if (!_isAssistant(req)) return _json(req, 401, {'error': 'Not allowed.'});
        return await _mcp(req, manager: path == '/mcp/manager');
      }
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
      // (The details stay here: they can show file paths and how the data is stored.)
      stderr.writeln('app ${spec.name}: $path failed: $e');
      return _json(req, 500, {'error': 'Something went wrong.'});
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
      // Lists whose cards show "3 places left" / "Full" (classes, courses, events).
      'places': [for (final t in spec.tables) if (spec.tables.any((b) => b.access.add && data.placeLinks(b).any((f) => f.link == t.id))) t.id],
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
      final ip = req.connectionInfo?.remoteAddress.address ?? '?';
      if (_lockedOut(ip)) return _json(req, 429, {'error': 'Too many wrong PINs. Try again in 15 minutes.'});
      if (sameSecret('${b['pin']}'.trim(), pin)) return _json(req, 200, {'ok': true});
      _failed(ip);
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
    if (rest == '_stats') {
      // Takings and how busy it is: the manager's dashboard only.
      if (!manager) return _json(req, 403, {'error': 'Only the manager can do that.'});
      return _json(req, 200, await data.stats());
    }
    if (rest.startsWith('_places/')) {
      // Places left on each class, course or event: counts only, never who booked.
      final t = spec.table(rest.substring(8));
      if (t == null || (!manager && !t.access.see)) return _json(req, 404, {'error': 'Not found'});
      return _json(req, 200, await data.placesLeft(t));
    }
    if (rest.startsWith('_stay/')) {
      // Which rooms are free for every night of a stay. Customers see rooms, never who is staying.
      final t = spec.table(rest.substring(6));
      final s = t == null ? null : AppData.stayOf(t);
      if (s == null || (!manager && !t!.access.add)) return _json(req, 404, {'error': 'Not found'});
      final q = req.uri.queryParameters;
      final from = parseDate(q['from'] ?? ''), to = parseDate(q['to'] ?? '');
      if (from == null || to == null || to.compareTo(from) <= 0) return _json(req, 400, {'error': 'Choose a check-out day after the check-in day.'});
      for (var d = DateTime.parse(from); d.isBefore(DateTime.parse(to)); d = DateTime(d.year, d.month, d.day + 1)) {
        final day = d.toIso8601String().substring(0, 10);
        final why = await data.closedOn(day);
        if (why != null) return _json(req, 200, {'nights': AppData.nights(from, to), 'free': const [], 'closed': why, 'closed_on': day});
      }
      final a = await data.freeStay(t!, from, to, guests: int.tryParse(q['guests'] ?? '') ?? 0);
      final rooms = spec.table(s.room.link!)!, minF = AppData.minNightsOf(rooms), n = AppData.nights(from, to);
      int min(Map<String, Object?> r) => minF == null ? 1 : ((r[minF.id] as num?)?.toInt() ?? 1);
      return _json(req, 200, {
        'nights': n,
        'free': [for (final r in a.free) if (min(r) <= n) r['id']],
        'too_short': {for (final r in a.free) if (min(r) > n) '${r['id']}': min(r)},
      });
    }
    if (rest.startsWith('_occupancy/')) {
      // Rooms by night with the guests' names: the manager's only.
      if (!manager) return _json(req, 403, {'error': 'Only the manager can do that.'});
      final t = spec.table(rest.substring(11));
      if (t == null || AppData.stayOf(t) == null) return _json(req, 404, {'error': 'Not found'});
      final q = req.uri.queryParameters;
      return _json(req, 200, await data.occupancy(t, parseDate(q['from'] ?? '') ?? DateTime.now().toIso8601String().substring(0, 10), days: int.tryParse(q['days'] ?? '') ?? 14));
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
    final keys = switch (b.type) {
      'hero' => const ['title', 'text', 'button', 'image'],
      'text' => const ['text'],
      'features' => const ['title', 'text'],
      'contact' => const ['title', 'text'],
      _ => const ['title'],
    };
    // A gallery's own pictures: the ones uploaded here, or on the web.
    if (b.type == 'gallery' && edit['images'] is List) {
      final imgs = [for (final x in edit['images'] as List) '$x'.trim()]..removeWhere((x) => !RegExp(r'^(/files/[a-z0-9]+\.(jpg|jpeg|png|webp|gif)|https://\S+)$').hasMatch(x));
      if (imgs.isEmpty) {
        d.remove('images');
      } else {
        d['images'] = imgs.take(24).toList();
      }
      if (d['images'] == null && d['table'] == null) return b;
    }
    for (final k in keys) {
      if (!edit.containsKey(k)) continue;
      final v = '${edit[k] ?? ''}'.trim();
      if (v.isEmpty && !((b.type == 'text' || b.type == 'features') && k == 'text')) {
        d.remove(k);
      } else {
        d[k] = v.length > 2000 ? v.substring(0, 2000) : v;
      }
    }
    if (b.type == 'hero' && (d['title'] ?? '').toString().isEmpty) return b;
    if (b.type == 'features' && '${d['text'] ?? ''}'.trim().isEmpty) return b;
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
        final shown = {...args}..remove('_heard'); // (the caller's words, for keeping who they asked for)
        try {
          if (paused) throw AppDataError('${spec.name} is paused right now.');
          final text = await callTool('${p['name']}', args, manager: manager);
          result = {'content': [{'type': 'text', 'text': text}]};
          onToolCall?.call(spec.name, '${p['name']}', shown, text, false);
        } on AppDataError catch (e) {
          result = {'content': [{'type': 'text', 'text': e.message}], 'isError': true};
          onToolCall?.call(spec.name, '${p['name']}', shown, e.message, true);
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
      final stay = AppData.stayOf(t);
      if (stay != null && !manager && t.access.add) {
        out.add(AppTool('check_${t.id}', 'For a NEW stay: shows which ${spec.table(stay.room.link!)!.title.toLowerCase()} of $app are free for every night from check-in to check-out. Not for someone\'s existing booking (that is find_my_${t.id}).', {
          stay.from.id: {'type': 'string', 'description': '${stay.from.label} (YYYY-MM-DD)'},
          stay.to.id: {'type': 'string', 'description': '${stay.to.label} (YYYY-MM-DD)'},
          if (stay.guests != null) stay.guests!.id: {'type': 'integer', 'description': 'How many people'},
        }, [stay.from.id, stay.to.id], readOnly: true));
      }
      final phoneF = t.fields.where((f) => f.type == 'phone').firstOrNull;
      if (!manager && t.access.add && !t.single && phoneF != null) {
        out.add(AppTool('find_my_${t.id}', 'Looks up the caller\'s EXISTING $what in $app by phone number — for "when is my booking?", "what time is my table?", "cancel/change my booking". Use it before saying anything about their booking. Needs their phone number AND the name it is under (ask for the name first).', {
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
          'name': {'type': 'string', 'description': 'The name it is booked under, as the caller said it'},
        }, const ['phone', 'name'], readOnly: true));
        out.add(AppTool('change_my_${t.id}', 'Changes one of the caller\'s own $what in $app (a new time or day, more people, other items…) instead of making a new one. Give only what changes. Only works for their phone number and the name it is under.', {
          'id': {'type': 'integer', 'description': 'Its id, from find_my_${t.id} (leave out if they have only one)'},
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
          'name': {'type': 'string', 'description': 'The name it is booked under, as the caller said it'},
          for (final f in fields) if (f.type != 'phone' && f.type != 'email' && !f.managerOnly && f.id != 'name' && f.id != t.labelField) f.id: _schema(f),
        }, const ['phone', 'name'], auto: true));
        out.add(AppTool('cancel_my_${t.id}', 'Cancels one of the caller\'s own $what in $app, after they confirmed which one. Only works for their phone number and the name it is under.', {
          'id': {'type': 'integer', 'description': 'Its id, from find_my_${t.id} (leave out if they have only one)'},
          'phone': {'type': 'string', 'description': 'The caller\'s phone number'},
          'name': {'type': 'string', 'description': 'The name it is booked under, as the caller said it'},
        }, const ['phone', 'name'], auto: true));
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
    if (phone.replaceAll(RegExp(r'\D'), '').length < 9) throw AppDataError('Ask for their phone number first.');
    // Two things, as a receptionist would check: the number they booked with (the number they are
    // calling from) and the name it is under. Without both, nothing about it is said or changed.
    final named = '${args['name'] ?? ''}'.trim();
    if (named.isEmpty || _placeholder.hasMatch(named)) {
      throw AppDataError('First ask the caller for the name the ${t.title.toLowerCase()} is under, then call this again with it (name). Say nothing about any booking until then.');
    }
    final what = t.title.toLowerCase();
    final shape = BookingShape.of(spec, t);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final mine = [
      for (final r in await data.list(t.id, manager: true))
        if (samePhone(r[phoneF.id], phone) && !(shape?.cancelled(r) ?? false) && (shape == null || '${r[shape.dateField.id] ?? ''}'.compareTo(today) >= 0)) r,
    ];
    final label = t.labelField;
    final onNumber = mine.length;
    mine.removeWhere((r) => !sameName(r[label], named));
    if (mine.isEmpty && onNumber > 0) {
      // On this number but under another name: maybe theirs (a partner's phone), maybe not — so no details.
      throw AppDataError('There is a ${t.title.toLowerCase()} on this number but not under the name "$named". For privacy, give no details of it: '
          'ask the caller for the exact name it was booked under. If they don\'t know it, they can\'t change or cancel it by phone.');
    }
    if (!cancel) {
      if (mine.isEmpty) return 'No $what found for the phone number $phone under the name $named. Tell the caller you can\'t find one (they may have used another number or name).';
      return 'Found ${mine.length} for $named on $phone:\n'
          '${await data.describe(t.id, [for (final r in mine) {for (final e in r.entries) if (e.key != 'created_at' && e.key != 'via') e.key: e.value}])}';
    }
    // Which one: the id given if it's theirs; else, when they have just one, that one.
    final id = (args['id'] as num?)?.toInt() ?? int.tryParse('${args['id'] ?? ''}');
    var r = id == null ? null : await data.get(t.id, id, manager: true);
    if (r != null && (!samePhone(r[phoneF.id], phone) || !sameName(r[label], named))) {
      throw AppDataError('That $what is not under this phone number and name, so it can\'t be ${change ? 'changed' : 'cancelled'} from this number. Tell the caller to call from the number they booked with. Give no details of it.');
    }
    if (r == null || !mine.any((m) => m['id'] == r!['id'])) {
      if (mine.isEmpty) throw AppDataError('No $what found for the phone number $phone under the name $named, so there is nothing to ${change ? 'change' : 'cancel'}. Tell the caller.');
      if (mine.length > 1) {
        throw AppDataError('They have ${mine.length}: ask which one, then call again with its id.\n${await data.describe(t.id, mine)}');
      }
      r = mine.single;
    }
    final rid = r['id'] as int;
    if (change) {
      // Never who it belongs to: not its phone number (whatever the field is called) or the name it is under.
      final fixed = {'id', 'phone', 'name', phoneF.id, label, for (final f in t.fields) if (f.type == 'phone' || f.type == 'email') f.id};
      await data.change(t.id, rid, {for (final e in args.entries) if (!fixed.contains(e.key) && e.value != null && '${e.value}'.isNotEmpty) e.key: e.value});
      return 'Done. Changed (the old details are replaced):\n${await data.describe(t.id, [(await data.get(t.id, rid, manager: true))!])}';
    }
    final status = shape?.statusField ?? statusOf(t);
    final cancelled = status?.options.where((o) => RegExp(r'cancel', caseSensitive: false).hasMatch(o)).firstOrNull;
    if (status != null && cancelled != null) {
      await data.update(t.id, rid, {status.id: cancelled});
    } else {
      await data.delete(t.id, rid);
    }
    return 'Cancelled. ${await data.describe(t.id, [r])}';
  }

  /// [args] with the stylist, doctor… the caller named: the one named just now, whatever the AI put in;
  /// else one named earlier in the call, when the AI left it out.
  Future<Map<String, dynamic>> _keepNamed(TableSpec t, Map<String, dynamic> args, List<String> heard) async {
    final shape = BookingShape.of(spec, t);
    if (shape == null || heard.isEmpty) return args;
    final res = shape.resourceField.id;
    final now = await data.namedResource(shape, heard.last);
    if (now != null) return {...args, res: now};
    if ('${args[res] ?? ''}'.trim().isNotEmpty) return args;
    final named = await data.namedResource(shape, heard.join('\n'));
    return named == null ? args : {...args, res: named};
  }

  static final _placeholder = RegExp(r'^((a|the|new|existing|regular|returning|valued)\s+)?(guest|customer|caller|client|unknown|n/?a|none|name|user|walk.?in|anonymous|patient|student|test|tbc|son|daughter|child|kid|boy|girl|wife|husband|partner|me|myself|mum|mom|dad|friend|\?+|-+)(\s*\d*)?$', caseSensitive: false);

  Future<String> callTool(String name, Map<String, dynamic> args, {required bool manager}) async {
    final tool = mcpTools(manager: manager).where((t) => t.name == name).firstOrNull;
    if (tool == null) throw AppDataError('Unknown tool $name.');
    // The caller's own words in the call (sent by the phone side), newest last: who they asked for is kept.
    final heard = [for (final x in (args['_heard'] as List? ?? const [])) '$x'];
    final since = (args['_since'] as num?)?.toInt(); // when this call started
    if (args.containsKey('_heard') || args.containsKey('_since')) args = {...args}..remove('_heard')..remove('_since');
    if (RegExp(r'^(find|cancel|change)_my_').hasMatch(name)) {
      if (name.startsWith('change_my_')) args = await _keepNamed(spec.table(name.substring(10))!, args, heard);
      return _mine(name, args);
    }
    final verb = name.substring(0, name.indexOf('_'));
    final t = spec.table(name.substring(verb.length + 1))!;
    switch (verb) {
      case 'check':
        final stay = AppData.stayOf(t);
        if (stay != null) {
          final from = parseDate('${args[stay.from.id] ?? ''}'), to = parseDate('${args[stay.to.id] ?? ''}');
          if (from == null || to == null) throw AppDataError('Give check-in and check-out as YYYY-MM-DD (today is ${withDay(DateTime.now().toIso8601String().substring(0, 10))}).');
          if (to.compareTo(from) <= 0) throw AppDataError('${stay.to.label} must be after ${stay.from.label.toLowerCase()}.');
          final guests = (args[stay.guests?.id] as num?)?.toInt() ?? int.tryParse('${args[stay.guests?.id] ?? ''}') ?? 0;
          for (var d = DateTime.parse(from); d.isBefore(DateTime.parse(to)); d = DateTime(d.year, d.month, d.day + 1)) {
            final day = d.toIso8601String().substring(0, 10);
            final why = await data.closedOn(day);
            if (why != null) return AppData.closedMessage(day, why);
          }
          final all = await data.freeStay(t, from, to, guests: guests);
          final rooms = spec.table(stay.room.link!)!, label = rooms.labelField, minF = AppData.minNightsOf(rooms);
          final nights = DateTime.parse('${to}T00:00:00Z').difference(DateTime.parse('${from}T00:00:00Z')).inDays;
          // A room let for a minimum number of nights isn't offered for a shorter stay.
          int min(Map<String, Object?> r) => minF == null ? 1 : ((r[minF.id] as num?)?.toInt() ?? 1);
          final a = (free: [for (final r in all.free) if (min(r) <= nights) r], taken: all.taken);
          final short = [for (final r in all.free) if (min(r) > nights) '${r[label]} (at least ${min(r)} nights)'];
          final booked = (a.taken.isEmpty ? '' : 'Booked then: ${a.taken.map((r) => r[label]).join(', ')}. ') + (short.isEmpty ? '' : 'Only for longer stays: ${short.join(', ')}. ');
          if (a.free.isEmpty) return 'Nothing is free for all $nights nights, ${withDay(from)} to ${withDay(to)}${guests > 0 ? ' for $guests' : ''}. ${booked}Ask whether other dates suit them.';
          return 'Free for all $nights nights, ${withDay(from)} to ${withDay(to)}${guests > 0 ? ' for $guests' : ''}: ${a.free.map((r) => r[label]).join(', ')}. $booked'
              'This only checked — NOTHING IS BOOKED YET. Once you have the caller\'s name and phone and they agree, call add_${t.id} with one of the free ones.';
        }
        final b = BookingShape.of(spec, t)!;
        final date = parseDate('${args['date'] ?? ''}') ?? (throw AppDataError('Give the date as YYYY-MM-DD (today is ${withDay(DateTime.now().toIso8601String().substring(0, 10))}).'));
        final time = parseTime('${args['time'] ?? ''}') ?? (throw AppDataError('Give the time as HH:MM, 24-hour (7pm = 19:00).'));
        final guests = (args['guests'] as num?)?.toInt() ?? int.tryParse('${args['guests'] ?? ''}') ?? 0;
        // A holiday or other closed day: say so, rather than "nothing is free".
        final why = await data.closedOn(date);
        if (why != null) return AppData.closedMessage(date, why);
        final a = await data.availability(b, date, time, guests: guests);
        final area = b.resources.fields.where((f) => f.type == 'choice').firstOrNull;
        String show(Map<String, Object?> r) => '${r[b.resources.labelField] ?? r['id']}${b.seatsField != null ? ' (${r[b.seatsField!.id]} seats${area != null && r[area.id] != null ? ', ${r[area.id]}' : ''})' : ''}';
        final what = b.resources.title.toLowerCase();
        final on = withDay(date);
        if (a.free.isEmpty) {
          // Real times to offer ("11:00 or 13:00?"), not just "another time?".
          final near = await data.nearestFree(b, date, time, guests: guests);
          return 'Nothing is free at $time on $on${guests > 0 ? ' for $guests' : ''}. '
              '${near.isEmpty ? 'Nothing else is free that day: ask which other day suits them.' : 'Free that day at: ${near.join(', ')}. Offer the nearest of these (nothing is booked yet).'}';
        }
        return 'Free $what at $time on $on${guests > 0 ? ' for $guests' : ''}: ${a.free.map(show).join(', ')}. '
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
          // A name the caller never said ("Birthday Group", the owner's name): ask for it. (Spelt out letters count;
          // so does a near spelling, as speech-to-text writes names loosely.)
          if (heard.isNotEmpty) {
            final said = plain(heard.join(' '));
            final letters = said.replaceAll(RegExp(r'[^a-z]'), '');
            final words = said.split(RegExp(r'[^a-z]+')).where((w) => w.length >= 3).toSet();
            bool near(String a, String b) {
              if ((a.length - b.length).abs() > 2) return false;
              var prev = List<int>.generate(b.length + 1, (i) => i);
              for (var i = 1; i <= a.length; i++) {
                final cur = [i, ...List<int>.filled(b.length, 0)];
                for (var j = 1; j <= b.length; j++) {
                  cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
                }
                prev = cur;
              }
              return prev[b.length] <= (a.length > 5 ? 2 : 1);
            }

            for (final f in t.fields.where((f) => f.type == 'text' && RegExp(r'^(name|student|patient)$|your name|patient name|student name', caseSensitive: false).hasMatch('${f.id}|${f.label}'.split('|').first == 'name' ? 'name' : f.label))) {
              final parts = plain('${args[f.id] ?? ''}').split(RegExp(r'[^a-z]+')).where((w) => w.length >= 3).toList();
              if (parts.isNotEmpty && !parts.any((p) => words.contains(p) || letters.contains(p) || words.any((w) => near(w, p)))) {
                throw AppDataError('Ask the caller for their ${f.label.toLowerCase().replaceFirst('your ', '')} first ("${args[f.id]}" was never said), then save it.');
              }
            }
          }
          // A phone number without its digits ("Lily"), or "unknown" for something required: ask for it.
          for (final f in t.fields.where((f) => !f.managerOnly)) {
            final v = '${args[f.id] ?? ''}'.trim();
            if (v.isEmpty) continue;
            if (f.type == 'phone' && v.replaceAll(RegExp(r'\D'), '').length < 7) throw AppDataError('Ask the caller for their phone number first ("$v" is not one), then save it.');
            if (f.required && f.type == 'text' && RegExp(r'^(unknown|n/?a|none|tbc|tbd|not given|not provided|\?+|-+)$', caseSensitive: false).hasMatch(v)) {
              throw AppDataError('Ask the caller for the ${f.label.toLowerCase().replaceFirst('your ', '')} first ("$v" is not one), then save it.');
            }
          }
        }
        if (!manager) {
          // The stylist, doctor or barber the caller asked for (else the first free one is given).
          args = await _keepNamed(t, args, heard);
          // Saved already in this call (the caller corrected something, or the AI saved twice): change that one —
          // unless they asked for two ("also a table on Saturday", "both").
          final two = heard.any((h) => RegExp(r'\b(also|another|second|both)\b[^.?!]{0,40}\b(book|table|appointment|reservation|order|room|stay)|\btwo (tables|bookings|appointments|orders)\b', caseSensitive: false).hasMatch(h));
          final shape = BookingShape.of(spec, t);
          final prev = await data.recentByPhone(t, '${args[t.fields.where((f) => f.type == 'phone').firstOrNull?.id] ?? ''}',
              date: shape == null ? null : parseDate('${args[shape.dateField.id] ?? ''}'), name: '${args[t.labelField] ?? ''}', since: since);
          if (prev != null && !two) {
            await data.change(t.id, prev, args);
            return 'Done. Updated the one saved earlier in this call (not a second one):\n${await data.describe(t.id, [(await data.get(t.id, prev, manager: false))!])}';
          }
        }
        data.autoSwap = !manager;
        data.swapped = null;
        final int id;
        try {
          id = await data.add(t.id, args, manager: manager, via: 'phone').catchError((Object e) async {
            // A table/stylist that isn't one ("inside"): it may be left out (the best free one is given).
            final res = BookingShape.of(spec, t)?.resourceField;
            if (manager || res == null || e is! AppDataError || !e.message.startsWith('${res.label}: "')) throw e;
            return data.add(t.id, {...args}..remove(res.id), manager: manager, via: 'phone');
          });
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
  // A whole number (9+ digits): "123456" must not match everyone whose number ends that way.
  if (x.length < 9 || y.length < 9) return false;
  return x.substring(x.length - 9) == y.substring(y.length - 9);
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

/// Two secrets the same, taking the same time whatever they are (no clues from timing).
bool sameSecret(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

/// The same person's name, allowing for how it was heard or spelt ("Tariq" / "Tarek", "Jon" / "John"):
/// a first name or surname of at least three letters in both, within a letter or two.
bool sameName(Object? a, Object? b) {
  List<String> parts(Object? x) => plain('$x').split(RegExp(r'[^a-z]+')).where((w) => w.length >= 3).toList();
  int dist(String p, String q) {
    var prev = List<int>.generate(q.length + 1, (i) => i);
    for (var i = 1; i <= p.length; i++) {
      final cur = [i, ...List<int>.filled(q.length, 0)];
      for (var j = 1; j <= q.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (p[i - 1] == q[j - 1] ? 0 : 1)].reduce((m, n) => m < n ? m : n);
      }
      prev = cur;
    }
    return prev[q.length];
  }

  final x = parts(a), y = parts(b);
  return x.any((p) => y.any((q) => p == q || dist(p, q) <= (p.length >= 5 ? 2 : 1)));
}
