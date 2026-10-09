/// Every ready-made app, without the AI: its website forms and its tools for callers (MCP),
/// the way a customer and the phone assistant use them. Fast (no model needed).
///   flutter test test/scenarios/website_mcp_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_apps/app_data.dart';
import 'package:localailine_apps/app_spec.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_apps/apps_manager.dart';
import 'package:localailine_core/services/mcp/mcp_manager.dart';
import 'package:localailine/state/app_state.dart';

String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
final tomorrow = ymd(DateTime.now().add(const Duration(days: 1)));

void main() {
  HttpOverrides.global = null;
  late Db db;
  late AppsManager apps;
  final ids = <String, int>{};
  final http = HttpClient();

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('webmcp');
    db = await Db.open(path: '${tmp.path}/t.db');
    apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    for (final t in appTemplates) {
      ids[t.id] = await apps.createFromTemplate(t, ava: false);
      await apps.start(ids[t.id]!, quiet: true);
      // The sample closed days (Christmas…) would make these tests depend on the date they run;
      // closed days have their own tests (app_pro_test.dart).
      final s = (await apps.app(ids[t.id]!))!.spec;
      final c = closuresOf(s);
      if (c != null) {
        final d = AppData(db, ids[t.id]!, s);
        for (final r in await d.list(c.id, manager: true)) {
          await d.delete(c.id, r['id'] as int);
        }
      }
    }
  });
  tearDownAll(() => apps.stopAll());

  Future<AppSpec> spec(String app) async => (await apps.app(ids[app]!))!.spec;
  AppData data(String app, AppSpec s) => AppData(db, ids[app]!, s);

  Future<({int code, dynamic body})> req(String app, String method, String path, {Object? body, bool manager = false}) async {
    final a = (await apps.app(ids[app]!))!;
    final rq = await http.openUrl(method, Uri.parse('http://127.0.0.1:${a.port}$path'));
    // The site's own header on every request (the website always sends it), and the tools' key.
    rq.headers.set('x-key', manager ? a.pin : '');
    if (path.startsWith('/mcp')) rq.headers.set('x-tool-key', await apps.toolKey(ids[app]!));
    if (body != null) {
      rq.headers.contentType = ContentType.json;
      rq.write(jsonEncode(body));
    }
    final rs = await rq.close();
    final text = await utf8.decodeStream(rs);
    return (code: rs.statusCode, body: text.startsWith('{') || text.startsWith('[') ? jsonDecode(text) : text);
  }

  Future<({bool error, String text})> tool(String app, String name, Map<String, dynamic> args) async {
    final r = await req(app, 'POST', '/mcp', body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': name, 'arguments': args}});
    final res = (r.body as Map)['result'] as Map;
    return (error: res['isError'] == true, text: '${(res['content'] as List).first['text']}');
  }

  Future<List<String>> toolNames(String app) async {
    final r = await req(app, 'POST', '/mcp', body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'});
    return [for (final t in ((r.body as Map)['result']['tools'] as List)) '${t['name']}'];
  }

  /// A valid record for a table, made from its fields (links: the first record, by name).
  Future<Map<String, dynamic>> valid(String app, TableSpec t, {String phone = '07700 900111', int salt = 0}) async {
    final s = await spec(app);
    final d = data(app, s);
    final v = <String, dynamic>{};
    for (final f in t.fields.where((f) => !f.managerOnly)) {
      if (!f.required && !const {'phone', 'date', 'time', 'number'}.contains(f.type)) continue;
      Future<String> firstName() async {
        final lt = s.table(f.link!)!;
        final rows = await d.list(lt.id, manager: true);
        return '${rows[salt % rows.length][lt.labelField]}';
      }
      v[f.id] = switch (f.type) {
        'phone' => phone,
        'email' => 'test$salt@example.com',
        'date' => ymd(DateTime.now().add(Duration(days: 7 + salt * 10))),
        'time' => '${(13 + salt % 4).toString().padLeft(2, '0')}:00', // (when every template is open)
        'datetime' => '$tomorrow 17:00',
        'number' || 'money' => 2,
        'choice' => f.options.first,
        'link' => await firstName(),
        'links' => f.qty ? [{'item': await firstName(), 'qty': 2}] : [await firstName()],
        _ => 'Test Person $salt',
      };
    }
    // Check-out after check-in.
    final dates = t.fields.where((f) => f.type == 'date').toList();
    if (dates.length > 1) v[dates[1].id] = ymd(DateTime.now().add(Duration(days: 9 + salt * 10)));
    return v;
  }

  for (final tpl in appTemplates) {
    group('${tpl.id}:', () {
      test('website opens, pages and lists work, private tables stay private', () async {
        final s = await spec(tpl.id);
        expect((await req(tpl.id, 'GET', '/')).code, 200);
        for (final p in s.pages) {
          expect((await req(tpl.id, 'GET', '/p/${p.id}')).code, 200, reason: p.id);
        }
        for (final t in s.tables) {
          final r = await req(tpl.id, 'GET', '/api/t/${t.id}');
          if (t.access.see) {
            expect(r.code, 200, reason: t.id);
          } else {
            expect(r.code, 403, reason: '${t.id}: customers must not see other people\'s ${t.title}');
          }
        }
        expect((await req(tpl.id, 'GET', '/manage')).code, 200);
      });

      for (final t in tpl.spec['tables'] as List) {
        final tid = (t as Map)['id'] as String;
        if (t['access'] != 'add') continue;
        test('$tid: a customer\'s form is saved and the manager sees it', () async {
          final s = await spec(tpl.id);
          final table = s.table(tid)!;
          final v = await valid(tpl.id, table, salt: 1);
          final r = await req(tpl.id, 'POST', '/api/t/$tid', body: {...v, 'status': 'Cancelled'});
          expect(r.code, 200, reason: '${r.body}');
          final rows = (await req(tpl.id, 'GET', '/api/t/$tid', manager: true)).body as List;
          final row = rows.firstWhere((x) => x['id'] == (r.body as Map)['id']);
          final st = table.fields.where((f) => f.managerOnly && f.type == 'choice').firstOrNull;
          if (st != null) expect(row[st.id], st.options.first, reason: 'customers can\'t set the status');
          expect(row['via'] ?? row['_via'], anyOf('website', null));
        });

        test('$tid: every required field is asked for', () async {
          final s = await spec(tpl.id);
          final table = s.table(tid)!;
          final v = await valid(tpl.id, table, salt: 2);
          for (final f in table.fields.where((f) => f.required && !f.managerOnly && f.when == null)) {
            final r = await req(tpl.id, 'POST', '/api/t/$tid', body: {...v}..remove(f.id));
            expect(r.code, 400, reason: '${f.id} left out');
            expect('${(r.body as Map)['error']}', contains(f.label));
          }
        });

        test('$tid: the phone tools for callers', () async {
          final s = await spec(tpl.id);
          final table = s.table(tid)!;
          final names = await toolNames(tpl.id);
          expect(names, contains('add_$tid'));
          final hasPhone = table.fields.any((f) => f.type == 'phone');
          if (!hasPhone) return;
          expect(names, containsAll(['find_my_$tid', 'cancel_my_$tid']));
          // A caller books by phone…
          final mine = await valid(tpl.id, table, phone: '+447700900555', salt: 3);
          final added = await tool(tpl.id, 'add_$tid', mine);
          expect(added.error, false, reason: added.text);
          final other = await valid(tpl.id, table, phone: '+447700900666', salt: 4);
          final added2 = await tool(tpl.id, 'add_$tid', other);
          expect(added2.error, false, reason: added2.text);
          // …finds only their own…
          final who = '${mine[table.labelField]}';
          // (Their number AND the name it's under: without the name, nothing is said.)
          final noName = await tool(tpl.id, 'find_my_$tid', {'phone': '07700 900555'});
          expect(noName.error, true);
          expect(noName.text, isNot(contains('900555')));
          final found = await tool(tpl.id, 'find_my_$tid', {'phone': '07700 900555', 'name': who});
          expect(found.text, contains('Found 1'));
          expect(found.text, isNot(contains('900666')));
          expect((await tool(tpl.id, 'find_my_$tid', {'phone': '+447700900777', 'name': who})).text, contains('No '));
          // The right number with a name that isn't on it: no details at all.
          final wrongName = await tool(tpl.id, 'find_my_$tid', {'phone': '07700 900555', 'name': 'Zebedee Quarrington'});
          expect(wrongName.error, true);
          for (final v in mine.values.whereType<String>().where((v) => v.length > 3 && !v.startsWith('+'))) {
            expect(wrongName.text, isNot(contains(v)), reason: 'nothing of the booking is given');
          }
          // …can't cancel someone else's…
          final theirs = ((await req(tpl.id, 'GET', '/api/t/$tid', manager: true)).body as List).firstWhere((r) => '${r['phone']}'.contains('900666'));
          final bad = await tool(tpl.id, 'cancel_my_$tid', {'phone': '+447700900555', 'name': who, 'id': theirs['id']});
          expect(bad.error, true);
          expect(bad.text, contains('not under this phone number'));
          final nobody = await tool(tpl.id, 'cancel_my_$tid', {'phone': '+447700900999', 'name': who});
          expect(nobody.error, true);
          // Their number said aloud by someone else: the tools only take a whole number (9+ digits).
          expect((await tool(tpl.id, 'find_my_$tid', {'phone': '900555', 'name': who})).error, true);
          // …and cancels their own.
          final ok = await tool(tpl.id, 'cancel_my_$tid', {'phone': '+44 7700 900555', 'name': who});
          expect(ok.error, false, reason: ok.text);
          final rows = (await req(tpl.id, 'GET', '/api/t/$tid', manager: true)).body as List;
          final st = table.fields.where((f) => f.managerOnly && f.type == 'choice').first.id;
          expect(rows.firstWhere((r) => r['id'] == theirs['id'])[st], isNot(contains('Cancel')), reason: 'the other caller\'s is untouched');
          expect(rows.where((r) => '${r['phone']}'.contains('900555')).every((r) => '${r[st]}'.contains('Cancel')), true);
        });

        test('$tid: the same booking twice (asked twice on a call) is kept once', () async {
          final s = await spec(tpl.id);
          final v = await valid(tpl.id, s.table(tid)!, phone: '+447700900321', salt: 5);
          final a = await tool(tpl.id, 'add_$tid', v), b = await tool(tpl.id, 'add_$tid', v);
          expect(a.error || b.error, false, reason: '${a.text} / ${b.text}');
          final rows = (await req(tpl.id, 'GET', '/api/t/$tid', manager: true)).body as List;
          expect(rows.where((r) => '${r['phone']}'.contains('900321')).length, 1);
        });
      }

      test('paused: the website and the tools say so, nothing is saved', () async {
        final id = ids[tpl.id]!;
        await apps.pause(id);
        try {
          final s = await spec(tpl.id);
          final t = s.tables.firstWhere((t) => t.access.add);
          expect((await req(tpl.id, 'POST', '/api/t/${t.id}', body: await valid(tpl.id, t, salt: 6))).code, 503);
          final r = await tool(tpl.id, 'add_${t.id}', await valid(tpl.id, t, salt: 6));
          expect(r.error, true);
          expect(r.text, contains('paused'));
        } finally {
          await apps.start(id, quiet: true);
        }
      });
    });
  }

  test('a time without am/pm means when the business is open; outside opening hours is refused', () async {
    // On a call "7:30" was checked as 07:30 (the restaurant opens at noon) and found "free".
    final date = ymd(DateTime.now().add(const Duration(days: 21)));
    final evening = await tool('restaurant', 'check_reservations', {'date': date, 'time': '7:30', 'guests': 2});
    expect(evening.text, contains('19:30'));
    final morning = await tool('restaurant', 'check_reservations', {'date': date, 'time': '23:30', 'guests': 2});
    expect(morning.text, contains('open from'));
    final s = await spec('restaurant');
    final add = await tool('restaurant', 'add_reservations', {...await valid('restaurant', s.table('reservations')!, salt: 9), 'date': date, 'time': '23:00'});
    expect(add.error, true);
    expect(add.text, contains('open from'));
  });

  group('bookings never clash:', () {
    for (final (app, table, res) in [('restaurant', 'reservations', 'table'), ('barber', 'appointments', 'barber'), ('salon', 'appointments', 'stylist'), ('clinic', 'appointments', 'doctor')]) {
      test('$app: same $res at the same time is refused; none chosen gets a free one; all busy is refused', () async {
        final s = await spec(app);
        final t = s.table(table)!;
        final d = data(app, s);
        final shape = BookingShape.of(s, t)!;
        final resources = await d.list(shape.resources.id, manager: true);
        final date = ymd(DateTime.now().add(const Duration(days: 20)));
        final base = await valid(app, t, salt: 7);
        final one = {...base, 'date': date, 'time': '14:00', res: '${resources.first[shape.resources.labelField]}', 'phone': '07700 100001'};
        expect((await tool(app, 'add_$table', one)).error, false);
        if (shape.seatsField != null) {
          // Restaurant tables: on the phone a taken table is swapped for a free one (and the AI is told); the website still refuses.
          final clash = await tool(app, 'add_$table', {...one, 'name': 'Second Person', 'phone': '07700 100002'});
          expect(clash.error, false, reason: clash.text);
          expect(clash.text, contains('was taken'));
          await tool(app, 'cancel_my_$table', {'phone': '07700 100002', 'name': 'Second Person'});
          final web = await req(app, 'POST', '/api/t/$table', body: {...one, 'name': 'Web Person', 'phone': '07700 100004'});
          expect(web.code, 400);
        } else {
          final clash = await tool(app, 'add_$table', {...one, 'name': 'Second Person', 'phone': '07700 100002'});
          expect(clash.error, true);
          expect(clash.text, contains('already booked'));
          // Half an hour later still overlaps (a booking lasts a while).
          final overlap = await tool(app, 'add_$table', {...one, 'name': 'Third', 'phone': '07700 100003', 'time': '14:15'});
          expect(overlap.error, true);
        }
        // No resource chosen: a free one is given, never the taken one.
        final rest = <int>[];
        for (var i = 0; i < resources.length - 1; i++) {
          final r = await tool(app, 'add_$table', {...one, res: null, 'name': 'Auto $i', 'phone': '07700 2000$i${i}0', if (shape.guestsField != null) shape.guestsField!.id: 2}..remove(res));
          expect(r.error, false, reason: r.text);
          rest.add(i);
        }
        final rows = [for (final r in await d.list(table, manager: true)) if (r[shape.dateField.id] == date && r[shape.timeField.id] == '14:00' && !shape.cancelled(r)) r[res]];
        expect(rows.toSet().length, rows.length, reason: 'nobody shares a $res');
        final full = await tool(app, 'add_$table', {...one, 'name': 'Late', 'phone': '07700 300003'}..remove(res));
        expect(full.error, true);
        expect(full.text, contains('nothing is free'));
        // The check tool agrees.
        final check = await tool(app, 'check_$table', {'date': date, 'time': '14:00', if (shape.guestsField != null) 'guests': 2});
        expect(check.text, contains('Nothing is free'));
        // A cancelled booking frees its slot.
        final first = (await d.list(table, manager: true)).firstWhere((r) => r['phone'] == '07700 100001');
        expect((await tool(app, 'cancel_my_$table', {'phone': '07700 100001', 'name': '${first[t.labelField]}', 'id': first['id']})).error, false);
        final again = await tool(app, 'add_$table', {...one, 'name': 'Gets the freed one', 'phone': '07700 100009'});
        expect(again.error, false, reason: again.text);
      });
    }

    test('restaurant: a party bigger than any table is refused; a party gets a table big enough', () async {
      final s = await spec('restaurant');
      final date = ymd(DateTime.now().add(const Duration(days: 21)));
      final base = {'name': 'Big Party', 'phone': '07700 400001', 'date': date, 'time': '19:00'};
      final big = await tool('restaurant', 'add_reservations', {...base, 'guests': 14});
      expect(big.error, true);
      final six = await tool('restaurant', 'add_reservations', {...base, 'guests': 6, 'phone': '07700 400002'});
      expect(six.error, false, reason: six.text);
      final d = data('restaurant', s);
      final row = (await d.list('reservations', manager: true)).firstWhere((r) => r['phone'] == '07700 400002');
      final table = (await d.list('dining_tables', manager: true)).firstWhere((t) => t['id'] == row['table']);
      expect(table['seats'] as num, greaterThanOrEqualTo(6));
    });

    test('hotel: a room is never booked twice for the same nights', () async {
      final d0 = DateTime.now().add(const Duration(days: 30));
      String day(int n) => ymd(d0.add(Duration(days: n)));
      final base = {'name': 'Guest One', 'phone': '07700 500001', 'room': 'Harbour View', 'guests': 2, 'check_in': day(0), 'check_out': day(3)};
      expect((await tool('hotel', 'add_bookings', base)).error, false);
      final overlap = await tool('hotel', 'add_bookings', {...base, 'name': 'Guest Two', 'phone': '07700 500002', 'check_in': day(2), 'check_out': day(4)});
      expect(overlap.error, true);
      expect(overlap.text, contains('already booked'));
      expect(overlap.text, contains('The Loft'), reason: 'offers what is free');
      final after = await tool('hotel', 'add_bookings', {...base, 'name': 'Guest Three', 'phone': '07700 500003', 'check_in': day(3), 'check_out': day(5)});
      expect(after.error, false, reason: 'checking in the day the last guest leaves is fine: ${after.text}');
      final backwards = await tool('hotel', 'add_bookings', {...base, 'name': 'Guest Four', 'phone': '07700 500004', 'room': 'The Loft', 'check_in': day(5), 'check_out': day(4)});
      expect(backwards.error, true);
    });
  });

  test('times and dates the way people and AIs say them are stored the same way', () {
    for (final (said, want) in [('19:30', '19:30'), ('7:30pm', '19:30'), ('7 pm', '19:00'), ('7.30 p.m.', '19:30'), ('12pm', '12:00'), ('12am', '00:00'), ('noon', '12:00'), ('09:05:00', '09:05'), ('7', null), ('25:00', null), ('soon', null)]) {
      expect(parseTime(said), want, reason: said);
    }
    final now = DateTime(2026, 10, 6); // a Tuesday
    for (final (said, want) in [('2026-10-10', '2026-10-10'), ('2026-10-10T19:00', '2026-10-10'), ('10/11/2026', '2026-11-10'), ('today', '2026-10-06'), ('tomorrow', '2026-10-07'), ('Saturday', '2026-10-10'), ('next Tuesday', '2026-10-13'), ('2026-02-30', null), ('someday', null)]) {
      expect(parseDate(said, now: now), want, reason: said);
    }
  });

  test('what the caller hears once it is saved', () {
    expect(AppEngine.doneLine('Done. Added to reservations with id 9:\nid 9 · Name: Freya Moreau · Phone: 0772 · Date: Saturday 2026-10-10 · Time: 19:10 · Guests: 2 · Table: 1 · Status: Confirmed'),
        'That’s all done: Saturday 10 October at 7:10 pm, for 2, table 1.');
    expect(AppEngine.doneLine('Cancelled. id 9 · Name: X'), 'That’s cancelled for you.');
  });

  test('the stylist, doctor or barber the caller asked for is kept', () async {
    final s = await spec('clinic');
    final d = data('clinic', s);
    final shape = BookingShape.of(s, s.table('appointments')!)!;
    expect(await d.namedResource(shape, 'Could I see Dr Reid on Friday?'), 'Dr Hannah Reid');
    expect(await d.namedResource(shape, 'with Omar please'), 'Dr Omar Khalil');
    expect(await d.namedResource(shape, 'Hannah, not Omar'), 'Dr Hannah Reid');
    expect(await d.namedResource(shape, 'any dentist is fine'), isNull);
    final b = await spec('barber');
    final bshape = BookingShape.of(b, b.table('appointments')!)!;
    expect(await data('barber', b).namedResource(bshape, 'A skin fade with Jay, not Tony'), 'Jay');
    // The phone tool keeps it even when the AI leaves it out.
    final r = await tool('clinic', 'add_appointments', {'name': 'Ana Lima', 'phone': '07700 900950', 'treatment': 'Check-up & clean', 'date': ymd(DateTime.now().add(const Duration(days: 33))), 'time': '10:00',
      '_heard': ['Hi, this is Ana Lima, a check-up please', 'With Dr Khalil if he is free']});
    expect(r.error, false, reason: r.text);
    expect(r.text, contains('Omar Khalil'));
  });

  test('a name the caller never said is refused; a spelt or near one is fine', () async {
    final date = ymd(DateTime.now().add(const Duration(days: 44)));
    Future<({bool error, String text})> add(String name, List<String> heard, String phone) =>
        tool('restaurant', 'add_reservations', {'name': name, 'phone': phone, 'date': date, 'time': '13:00', 'guests': 2, '_heard': heard});
    expect((await add('Birthday Group', ['A table for two please', 'yes'], '07700 701001')).error, true);
    expect((await add('Siobhan Nguyen', ['It is S-I-O-B-H-A-N, N-G-U-Y-E-N'], '07700 701002')).error, false);
    expect((await add('Rhiannon Gallagher', ['my name is Rianon Galagher'], '07700 701003')).error, false, reason: 'speech-to-text spelling');
    expect((await add('Dana Lee', ['Dana Lee, two people at 1pm'], '07700 701004')).error, false);
  });

  test('a made-up table is left out, the best free one given', () async {
    final r = await tool('restaurant', 'add_reservations', {'name': 'Ola Berg', 'phone': '07700 701010', 'date': ymd(DateTime.now().add(const Duration(days: 45))), 'time': '13:00', 'guests': 2, 'table': 'inside'});
    expect(r.error, false, reason: r.text);
  });

  test('the caller is done: goodbye and hang up', () {
    for (final s in ['No, that\'s all, thanks. Bye!', 'Great, thank you, goodbye.', 'Gracias, adiós.', 'Merci, au revoir', 'Nothing else, have a good day']) {
      expect(AppEngine.callerDone(s), true, reason: s);
    }
    for (final s in ['Bye the way, can I also order a pizza?', 'That\'s all correct, but can I change the time?', 'Is that all?', 'Yes please book it', 'I\'d like to order, then bye']) {
      expect(AppEngine.callerDone(s), false, reason: s);
    }
    // Just thanks: asked "anything else?" first; a thanks after that ends it.
    expect(AppEngine.callerDone('Perfect, cheers!'), false);
    expect(AppEngine.callerDone('Perfect, cheers!', asked: 'Is there anything else I can help you with?'), true);
  });

  test('the day a caller means', () {
    final wed = DateTime(2026, 10, 7); // a Wednesday
    expect(spokenDates('a table for two tomorrow at 7', now: wed), {'2026-10-08'});
    expect(spokenDates('the day after tomorrow please', now: wed), {'2026-10-09'});
    expect(spokenDates('next Thursday at 10am', now: wed), {'2026-10-08', '2026-10-15'});
    expect(spokenDates('this Wednesday', now: wed), {'2026-10-07', '2026-10-14'});
    expect(spokenDates('Saturday, ten past seven', now: wed), {'2026-10-10', '2026-10-17'});
    expect(spokenDates('not Friday, Saturday', now: wed), <String>{}, reason: 'two days named: leave it to the AI');
    expect(spokenDates('on the 15th', now: wed), <String>{});
    expect(spokenDates('yes please', now: wed), <String>{});
  });

  test('items and services are found the way people say them', () {
    final menu = {1: 'Women’s cut & blow-dry', 2: 'Men’s cut', 3: 'Blow-dry', 4: 'Full head colour'};
    expect(bestMatch("women's cut and blow-dry", menu), 1);
    expect(bestMatch('a blow dry', menu), 3);
    expect(bestMatch('colour', menu), 4);
    expect(bestMatch('nails', menu), null);
    expect(bestMatch('tiramisu', {1: 'Tiramisù', 2: 'Limoncello sorbet'}), 1);
    final shop = {1: 'Free-range eggs (6)', 2: 'Butter croissant', 3: 'Extra-virgin olive oil', 4: 'Sourdough loaf'};
    expect(bestMatch('box of six eggs', shop), 1);
    expect(bestMatch('croissants', shop), 2);
    expect(bestMatch('a bottle of olive oil', shop), 3);
    final garage = {1: 'MOT test', 2: 'Interim service', 3: 'Full service', 4: 'Brake pads (front)'};
    expect(bestMatch('Standard MOT', garage), 1);
    expect(bestMatch('front brake pads', garage), 4);
    expect(bestMatch('service', garage), null, reason: 'interim or full: ask');
    final barber = {1: 'Classic cut', 2: 'Kids cut', 3: 'Cut & beard', 4: 'Beard trim'};
    expect(bestMatch('classic haircut', barber), 1);
    expect(bestMatch('kids cut for my son', barber), 2);
    expect(bestMatch('cut and beard', barber), 3);
  });

  test('out of stock can\'t be ordered, on the website or by phone', () async {
    final body = {'name': 'Nina Park', 'phone': '07700 900800', 'type': 'Collection', 'items': [{'item': 'Eco washing-up liquid', 'qty': 1}], 'pickup': '${ymd(DateTime.now().add(const Duration(days: 1)))} 10:00'};
    final web = await req('shop', 'POST', '/api/t/orders', body: body);
    expect(web.code, 400);
    expect('${(web.body as Map)['error']}', contains('out of stock'));
    final phone = await tool('shop', 'add_orders', body);
    expect(phone.error, true);
    expect((await req('shop', 'POST', '/api/t/orders', body: {...body, 'items': [{'item': 'Sourdough loaf', 'qty': 1}]})).code, 200);
  });

  test('a made-up name is refused on the phone', () async {
    final r = await tool('restaurant', 'add_reservations', {'name': 'Guest', 'phone': '07700 700001', 'date': ymd(DateTime.now().add(const Duration(days: 25))), 'time': '7pm', 'guests': 2});
    expect(r.error, true);
    expect(r.text, contains('Ask the caller'));
    final ok = await tool('restaurant', 'add_reservations', {'name': 'Guest Smith', 'phone': '07700 700001', 'date': ymd(DateTime.now().add(const Duration(days: 25))), 'time': '7pm', 'guests': 2});
    expect(ok.error, false, reason: ok.text);
    expect(ok.text, contains('19:00'));
  });

  group('changing a booking by phone', () {
    test('change_my_ moves the caller\'s own booking, onto a free table, and never someone else\'s', () async {
      final date = ymd(DateTime.now().add(const Duration(days: 40)));
      final s = await spec('restaurant');
      final d = data('restaurant', s);
      // The website form (not the phone): so the phone tool doesn't treat it as "saved in this call".
      final mine = await req('restaurant', 'POST', '/api/t/reservations', body: {'name': 'Rosa Diaz', 'phone': '07700 800001', 'date': date, 'time': '19:00', 'guests': 4});
      await req('restaurant', 'POST', '/api/t/reservations', body: {'name': 'Other', 'phone': '07700 800002', 'date': date, 'time': '21:00', 'guests': 4, 'table': '3'});
      final moved = await tool('restaurant', 'change_my_reservations', {'phone': '+447700800001', 'name': 'Rosa Diaz', 'time': '9pm'});
      expect(moved.error, false, reason: moved.text);
      expect(moved.text, contains('21:00'));
      final row = await d.get('reservations', (mine.body as Map)['id'] as int, manager: true);
      expect(row!['time'], '21:00');
      expect(row['table'], isNot((await d.list('dining_tables', manager: true)).firstWhere((t) => t['number'] == '3')['id']), reason: 'table 3 is taken at 21:00');
      expect((await d.list('reservations', manager: true)).where((r) => r['phone'] == '07700 800001').length, 1, reason: 'moved, not a second booking');
      final theirs = (await d.list('reservations', manager: true)).firstWhere((r) => r['phone'] == '07700 800002');
      final bad = await tool('restaurant', 'change_my_reservations', {'phone': '+447700800001', 'name': 'Rosa Diaz', 'id': theirs['id'], 'time': '22:00'});
      expect(bad.error, true);
      expect((await d.get('reservations', theirs['id'] as int, manager: true))!['time'], '21:00');
    });

    test('saving again in the same call corrects the first save instead of adding a second', () async {
      final date = ymd(DateTime.now().add(const Duration(days: 41)));
      final a = await tool('restaurant', 'add_reservations', {'name': 'Sam Hill', 'phone': '07700 800010', 'date': date, 'time': '19:00', 'guests': 2});
      expect(a.error, false, reason: a.text);
      final b = await tool('restaurant', 'add_reservations', {'name': 'Sam Hill', 'phone': '07700 800010', 'date': date, 'time': '20:30', 'guests': 3});
      expect(b.error, false, reason: b.text);
      expect(b.text, contains('Updated'));
      final rows = [for (final r in await data('restaurant', await spec('restaurant')).list('reservations', manager: true)) if (r['phone'] == '07700 800010') r];
      expect(rows.length, 1);
      expect(rows.single['time'], '20:30');
      expect(rows.single['guests'], 3);
      // An order corrected in the same call: one order, the last items.
      await tool('restaurant', 'add_orders', {'name': 'Sam Hill', 'phone': '07700 800010', 'type': 'Collection', 'items': [{'item': 'Margherita', 'qty': 1}]});
      final o = await tool('restaurant', 'add_orders', {'name': 'Sam Hill', 'phone': '07700 800010', 'type': 'Delivery', 'address': '1 Elm Grove', 'postcode': 'N7 8QJ', 'items': [{'item': 'Diavola', 'qty': 2}]});
      expect(o.text, contains('Total: £26'));
      final orders = [for (final r in await data('restaurant', await spec('restaurant')).list('orders', manager: true)) if (r['phone'] == '07700 800010') r];
      expect(orders.length, 1);
      expect(orders.single['type'], 'Delivery');
    });
  });

  group('restaurant orders: collection, delivery, eat in', () {
    Future<({int code, dynamic body})> order(Map<String, dynamic> extra) =>
        req('restaurant', 'POST', '/api/t/orders', body: {'name': 'Ana', 'phone': '07700 600001', 'items': [{'item': 'Margherita', 'qty': 2}, {'item': 'Tiramisù', 'qty': 1}], ...extra});

    test('collection needs no address or table', () async {
      final r = await order({'type': 'Collection', 'ready_at': '18:30'});
      expect(r.code, 200, reason: '${r.body}');
    });
    test('delivery needs the address and postcode', () async {
      expect((await order({'type': 'Delivery'})).code, 400);
      final noPc = await order({'type': 'Delivery', 'address': '4 Mill Lane'});
      expect(noPc.code, 400);
      expect('${(noPc.body as Map)['error']}', contains('Postcode'));
      final ok = await order({'type': 'Delivery', 'address': '4 Mill Lane', 'postcode': 'E1 6AN', 'phone': '07700 600002'});
      expect(ok.code, 200, reason: '${ok.body}');
      final row = ((await req('restaurant', 'GET', '/api/t/orders', manager: true)).body as List).firstWhere((r) => r['id'] == (ok.body as Map)['id']);
      expect(row['address'], '4 Mill Lane');
      expect(row['postcode'], 'E1 6AN');
      expect(row['table'], isNull);
    });
    test('eating in needs a table; a table on a delivery is dropped', () async {
      expect((await order({'type': 'Dine-in', 'phone': '07700 600003'})).code, 400);
      expect((await order({'type': 'Dine-in', 'table': '4', 'phone': '07700 600004'})).code, 200);
      final r = await order({'type': 'Delivery', 'address': '9 Elm Grove', 'postcode': 'N7 8QJ', 'table': '4', 'phone': '07700 600005'});
      final row = ((await req('restaurant', 'GET', '/api/t/orders', manager: true)).body as List).firstWhere((x) => x['id'] == (r.body as Map)['id']);
      expect(row['table'], isNull);
    });
    test('the phone tool explains what delivery needs', () async {
      final r = await req('restaurant', 'POST', '/mcp', body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'});
      final add = ((r.body as Map)['result']['tools'] as List).firstWhere((t) => t['name'] == 'add_orders');
      final props = add['inputSchema']['properties'] as Map;
      expect('${props['address']['description']}', contains('Delivery'));
      expect(add['inputSchema']['required'], isNot(contains('address')));
      final missing = await tool('restaurant', 'add_orders', {'name': 'Bo', 'phone': '07700 600006', 'type': 'Delivery', 'items': [{'item': 'Diavola'}]});
      expect(missing.error, true);
      expect(missing.text, contains('Delivery'));
    });
    test('an unknown dish is refused with the menu named', () async {
      final r = await tool('restaurant', 'add_orders', {'name': 'Cy', 'phone': '07700 600007', 'type': 'Collection', 'items': [{'item': 'Hawaiian pizza', 'qty': 1}]});
      expect(r.error, true);
    });
  });
}
