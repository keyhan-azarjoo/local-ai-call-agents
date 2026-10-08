import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_server.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/mcp/mcp_client.dart';
import 'package:localailine/state/app_state.dart';

/// Attacks on a business app: nobody gets at anyone else's data, whatever they try — the tools
/// without the assistant's key, guessing the PIN, another site posting behind a visitor's back,
/// part of someone's number, someone else's name, an app description that tries to make
/// customers' details public.
void main() {
  const key = 'security-test-tool-key-0123456789abcdef';
  late Directory tmp;
  late Db db;
  late AppData data;
  late AppServer srv;
  late String base;
  late int victim;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('security');
    db = await Db.open(path: '${tmp.path}/t.db');
    final t = appTemplates.firstWhere((t) => t.id == 'restaurant');
    final spec = AppSpec.fromJson(t.spec.cast<String, dynamic>());
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('apps', {'name': 'x', 'request': 'x', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': '482913', 'created_at': now, 'updated_at': now});
    data = AppData(db, id, spec);
    for (final r in t.rows['dining_tables']!) {
      await data.add('dining_tables', r.cast<String, dynamic>(), manager: true);
    }
    final day = DateTime.now().add(const Duration(days: 3)).toIso8601String().substring(0, 10);
    victim = await data.add('reservations', {'name': 'Victoria Stone', 'phone': '+442079460555', 'date': day, 'time': '19:00', 'guests': 2}, via: 'phone');
    srv = AppServer(data: data, pin: '482913', toolKey: key);
    await srv.start(0);
    base = 'http://127.0.0.1:${srv.port}';
  });

  tearDown(() async {
    await srv.stop();
    await db.raw.close();
    tmp.deleteSync(recursive: true);
  });

  Future<McpSession> tools({String? withKey = key}) async {
    final s = McpSession(HttpTransport('$base/mcp', headers: {'X-Tool-Key': ?withKey}));
    await s.initialize();
    return s;
  }

  test('the tools answer only the assistant (its key), not anyone on the network', () async {
    await expectLater(tools(withKey: null), throwsA(anything));
    await expectLater(tools(withKey: 'guess'), throwsA(anything));
    final raw = await http.post(Uri.parse('$base/mcp'), headers: {'Content-Type': 'application/json', 'X-Key': ''},
        body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'find_my_reservations', 'arguments': {'phone': '+442079460555', 'name': 'Victoria Stone'}}}));
    expect(raw.statusCode, 401);
    expect(raw.body, isNot(contains('Victoria')));
    expect((await (await tools()).listTools()).map((t) => t.name), contains('find_my_reservations'));
  });

  test('someone else\'s booking: not by part of the number, not by a different name, not by another number', () async {
    final s = await tools();
    for (final args in [
      {'phone': '0555', 'name': 'Victoria Stone'}, // the end of her number
      {'phone': '9460555', 'name': 'Victoria Stone'},
      {'phone': '+447700900123', 'name': 'Victoria Stone'}, // her name, another phone
      {'phone': '+442079460555', 'name': 'Mark Jones'}, // her phone (spoofed), another name
      {'phone': '+442079460555'}, // no name
    ]) {
      final r = await s.callTool('find_my_reservations', args);
      expect(r.text, isNot(contains('19:00')), reason: '$args');
      expect(r.text, isNot(contains('Found')), reason: '$args');
      final c = await s.callTool('cancel_my_reservations', args);
      expect(c.isError, isTrue, reason: '$args');
      final m = await s.callTool('change_my_reservations', {...args, 'time': '21:00'});
      expect(m.isError, isTrue, reason: '$args');
    }
    final row = (await data.get('reservations', victim, manager: true))!;
    expect(row['status'], isNot(contains('Cancel')));
    expect(row['time'], '19:00');
    // Her number and her name: she can.
    expect((await s.callTool('find_my_reservations', {'phone': '020 7946 0555', 'name': 'victoria stone'})).text, contains('19:00'));
  });

  test('a booking can\'t be moved to another number or name by changing it', () async {
    final s = await tools();
    final r = await s.callTool('change_my_reservations', {'phone': '+442079460555', 'name': 'Victoria', 'guests': 3, 'phone_number': '+447700900666', 'customer': 'Hacker'});
    expect(r.isError, isFalse, reason: r.text);
    final row = (await data.get('reservations', victim, manager: true))!;
    expect(row['phone'], '+442079460555');
    expect(row['name'], 'Victoria Stone');
    expect(row['guests'], 3);
  });

  test('saving with her name from another phone never takes over her booking', () async {
    final s = await tools();
    final day = DateTime.now().add(const Duration(days: 4)).toIso8601String().substring(0, 10);
    final r = await s.callTool('add_reservations', {'name': 'Victoria Stone', 'phone': '+447700900777', 'date': day, 'time': '20:00', 'guests': 2});
    expect(r.isError, isFalse, reason: r.text);
    final row = (await data.get('reservations', victim, manager: true))!;
    expect(row['phone'], '+442079460555');
    expect(row['time'], '19:00');
    expect(r.text, isNot(contains('9460555')));
  });

  test('guessing the manager PIN locks the guesser out', () async {
    for (var i = 0; i < 5; i++) {
      expect((await http.get(Uri.parse('$base/api/t/reservations'), headers: {'X-Key': '00000$i'})).statusCode, 403);
    }
    // Locked: even the right PIN is refused for a while (from this address).
    final locked = await http.get(Uri.parse('$base/api/t/reservations'), headers: {'X-Key': '482913'});
    expect(locked.statusCode, 403);
    expect(locked.body, isNot(contains('Victoria')));
    final login = await http.post(Uri.parse('$base/api/_login'), headers: {'X-Key': ''}, body: jsonEncode({'pin': '482913'}));
    expect(login.statusCode, 429);
  });

  test('another website can\'t post here behind a visitor\'s back, nor reach it by a look-alike name', () async {
    final day = DateTime.now().add(const Duration(days: 5)).toIso8601String().substring(0, 10);
    final body = jsonEncode({'name': 'Spam', 'phone': '07700 900111', 'date': day, 'time': '18:00', 'guests': 2});
    // A form post from another site has no X-Key header (it can't add one without asking first).
    expect((await http.post(Uri.parse('$base/api/t/reservations'), headers: {'Content-Type': 'text/plain'}, body: body)).statusCode, 403);
    expect((await http.post(Uri.parse('$base/api/t/reservations'), headers: {'X-Key': '', 'Host': 'evil.example.com'}, body: body)).statusCode, 403);
    expect((await http.post(Uri.parse('$base/api/t/reservations'), headers: {'X-Key': ''}, body: body)).statusCode, 200);
  });

  test('customers never list bookings, and see no one\'s details', () async {
    expect((await http.get(Uri.parse('$base/api/t/reservations'))).statusCode, 403);
    final plan = await http.get(Uri.parse('$base/api/_plan/reservations?date=${DateTime.now().add(const Duration(days: 3)).toIso8601String().substring(0, 10)}'));
    expect(plan.body, isNot(contains('Victoria')));
    expect(plan.body, isNot(contains('9460555')));
    final s = await tools();
    final check = await s.callTool('check_reservations', {'date': DateTime.now().add(const Duration(days: 3)).toIso8601String().substring(0, 10), 'time': '19:00', 'guests': 2});
    expect(check.text, isNot(contains('Victoria')));
  });

  group('apps the builder makes keep people\'s details private', () {
    AppSpec make(List<Map<String, Object?>> tables) => AppSpec.fromJson({
          'name': 'Test clinic',
          'tables': tables,
          'pages': [
            {'id': 'home', 'title': 'Home', 'blocks': []},
          ],
        });

    test('loose wording never makes a table public', () {
      expect(Access.fromJson('customers can\'t see this').see, isFalse);
      expect(Access.fromJson('all').see, isFalse);
      expect(Access.fromJson('none').see, isFalse);
      expect(Access.fromJson('manager only').see, isFalse);
      expect(Access.fromJson('see').see, isTrue);
      expect(Access.fromJson(['see', 'add']).add, isTrue);
    });

    test('a table customers add their details to is never listed to customers', () {
      final s = make([
        {'id': 'appointments', 'title': 'Appointments', 'access': 'see+add', 'fields': [
          {'id': 'name', 'label': 'Name', 'type': 'text'},
          {'id': 'phone', 'label': 'Phone', 'type': 'phone'},
          {'id': 'patient', 'label': 'Patient', 'type': 'link', 'link': 'patients'},
        ]},
        {'id': 'patients', 'title': 'Patients', 'access': 'none', 'fields': [
          {'id': 'name', 'label': 'Name', 'type': 'text'},
          {'id': 'phone', 'label': 'Phone', 'type': 'phone'},
          {'id': 'address', 'label': 'Home address', 'type': 'text'},
        ]},
      ]);
      expect(s.table('appointments')!.access.see, isFalse);
      expect(s.table('appointments')!.access.add, isTrue);
      expect(s.table('patients')!.access.see, isFalse, reason: 'not made public just because appointments link to it');
      expect(s.table('appointments')!.field('patient')!.managerOnly, isTrue);
    });
  });

  test('a caller\'s name is only taken from what they said', () {
    expect(AppState.saidName('Hi, my name is Hugo Khan and I want to cancel'), 'Hugo Khan');
    expect(AppState.saidName("It's under Patel, please"), 'Patel');
    expect(AppState.saidName("I'm calling from this phone number"), isNull);
    expect(sameName('Siobhan Evans', 'siobhan'), isTrue);
    expect(sameName('Tariq Ahmad', 'Tarek'), isTrue);
    expect(sameName('Victoria Stone', 'Mark Jones'), isFalse);
  });

  test('a parent who enrolled a student finds it under their own name; a stranger doesn\'t', () async {
    final t = appTemplates.firstWhere((t) => t.id == 'tutoring');
    final spec = AppSpec.fromJson(t.spec.cast<String, dynamic>());
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('apps', {'name': 'y', 'request': 'y', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': '111111', 'created_at': now, 'updated_at': now});
    final d = AppData(db, id, spec);
    for (final e in t.rows.entries) {
      for (final r in e.value) {
        try {
          await d.add(e.key, r.cast<String, dynamic>(), manager: true);
        } catch (_) {}
      }
    }
    final course = '${(await d.list('courses', manager: true)).first['name']}';
    await d.add('enrolments', {'student': 'Mei Stone', 'parent': 'Victoria Stone', 'phone': '+442079460555', 'course': course}, manager: true);
    final s2 = AppServer(data: d, pin: '111111', toolKey: key);
    await s2.start(0);
    final mcp = McpSession(HttpTransport('http://127.0.0.1:${s2.port}/mcp', headers: {'X-Tool-Key': key}));
    await mcp.initialize();
    expect((await mcp.callTool('find_my_enrolments', {'phone': '+442079460555', 'name': 'Victoria Stone'})).text, contains('Found 1'));
    expect((await mcp.callTool('find_my_enrolments', {'phone': '+442079460555', 'name': 'Mei'})).text, contains('Found 1'));
    expect((await mcp.callTool('find_my_enrolments', {'phone': '+442079460555', 'name': 'Mark Jones'})).isError, isTrue);
    expect((await mcp.callTool('find_my_enrolments', {'phone': '+447700900123', 'name': 'Victoria Stone'})).text, isNot(contains('Found')));
    await s2.stop();
  });
}
