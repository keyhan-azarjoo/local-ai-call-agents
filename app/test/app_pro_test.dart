/// The ready-made apps as professional products: new page blocks, the manager's dashboard numbers,
/// closed days, delivery fees and minimum orders, and that nothing old was renamed or reordered.
///   flutter test test/app_pro_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_server.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/mcp/mcp_client.dart';

const key = 'pro-test-tool-key-0123456789abcdefghij';
const pin = '246810';

/// Every table, field and choice the templates had before this upgrade (ids and options, in order),
/// and the restaurant's dishes and prices. Apps already made from them must keep working.
const before = r'''{"restaurant":{"menu_items":[["name",[]],["category",["Starters","Pizza","Pasta","Desserts","Drinks"]],["description",[]],["price",[]],["photo",[]],["vegetarian",[]],["spicy",[]]],"dining_tables":[["number",[]],["seats",[]],["area",["Inside","Terrace","Window"]]],"orders":[["name",[]],["phone",[]],["type",["Collection","Delivery","Dine-in"]],["address",[]],["postcode",[]],["table",[]],["ready_at",[]],["items",[]],["notes",[]],["status",["New","Preparing","Ready","Out for delivery","Done","Cancelled"]]],"reservations":[["name",[]],["phone",[]],["date",[]],["time",[]],["guests",[]],["table",[]],["requests",[]],["status",["Confirmed","Seated","Finished","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"salon":{"services":[["name",[]],["category",["Cut & style","Colour","Treatments","Nails"]],["description",[]],["duration",[]],["price",[]],["photo",[]]],"stylists":[["name",[]],["role",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["service",[]],["stylist",[]],["date",[]],["time",[]],["notes",[]],["status",["Confirmed","Done","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"barber":{"services":[["name",[]],["category",["Haircuts","Beard","Shaves","Kids"]],["description",[]],["duration",[]],["price",[]]],"barbers":[["name",[]],["speciality",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["service",[]],["barber",[]],["date",[]],["time",[]],["notes",[]],["status",["Booked","Done","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"gym":{"classes":[["name",[]],["day",["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]],["time",[]],["level",["All levels","Beginner","Advanced"]],["trainer",[]],["description",[]],["spots",[]],["photo",[]]],"trainers":[["name",[]],["speciality",[]],["bio",[]],["photo",[]]],"memberships":[["name",[]],["description",[]],["price",[]]],"signups":[["name",[]],["phone",[]],["email",[]],["class",[]],["date",[]],["status",["Booked","Attended","No-show","Cancelled"]]]},"shop":{"products":[["name",[]],["category",["Bakery","Fresh","Pantry","Drinks","Household"]],["description",[]],["price",[]],["photo",[]],["in_stock",[]]],"orders":[["name",[]],["phone",[]],["items",[]],["type",["Collection","Delivery"]],["address",[]],["postcode",[]],["pickup",[]],["notes",[]],["status",["New","Packing","Ready","Out for delivery","Collected","Delivered","Cancelled"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"clinic":{"treatments":[["name",[]],["description",[]],["duration",[]],["price",[]]],"doctors":[["name",[]],["role",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["email",[]],["treatment",[]],["doctor",[]],["date",[]],["time",[]],["reason",[]],["status",["Confirmed","Completed","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"hotel":{"rooms":[["name",[]],["description",[]],["guests",[]],["bed",["Double","King","Twin","Family"]],["price",[]],["sea_view",[]],["photo",[]]],"bookings":[["name",[]],["phone",[]],["email",[]],["room",[]],["check_in",[]],["check_out",[]],["guests",[]],["requests",[]],["status",["Requested","Confirmed","Checked in","Cancelled"]]]},"garage":{"services":[["name",[]],["description",[]],["price",[]],["time",[]]],"bookings":[["name",[]],["phone",[]],["car",[]],["plate",[]],["services",[]],["date",[]],["notes",[]],["status",["Booked","In the workshop","Ready","Collected","Cancelled"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"tutoring":{"courses":[["name",[]],["subject",["Maths","English","Science","Languages","Coding"]],["level",["Primary","GCSE","A-level","Adults"]],["schedule",[]],["description",[]],["price",[]],["photo",[]]],"enrolments":[["student",[]],["parent",[]],["phone",[]],["email",[]],["course",[]],["notes",[]],["status",["New","Confirmed","Waiting list","Cancelled"]]]},"events":{"events":[["name",[]],["date",[]],["time",[]],["genre",["Rock","Jazz","Electronic","Comedy","Folk"]],["description",[]],["price",[]],["photo",[]],["sold_out",[]]],"tickets":[["name",[]],["phone",[]],["email",[]],["event",[]],["quantity",[]],["status",["Requested","Paid","Sent","Cancelled"]]]},"realestate":{"listings":[["title",[]],["type",["Sale","Rent"]],["price",[]],["bedrooms",[]],["area",[]],["description",[]],["photo",[]],["available",[]]],"viewings":[["name",[]],["phone",[]],["email",[]],["property",[]],["date",[]],["message",[]],["status",["New","Booked","Viewed","Offer made","Closed"]]]},"_menu":[["Burrata & heritage tomatoes",9.5],["Fritto misto",11],["Margherita",10.5],["Diavola",13],["Tartufo",15],["Cacio e pepe",12.5],["Linguine allo scoglio",18],["Tiramisù",7],["Limoncello sorbet",6],["Aperol spritz",9],["San Pellegrino",4]]}''';

String ymd(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  final restaurantTpl = appTemplates.firstWhere((t) => t.id == 'restaurant');

  group('templates', () {
    test('existing tables, fields and options keep their ids and order; new ones only come after', () {
      final snap = jsonDecode(before) as Map<String, dynamic>;
      for (final tpl in appTemplates) {
        final old = snap[tpl.id] as Map<String, dynamic>;
        final tables = [for (final t in (tpl.spec['tables'] as List).cast<Map>()) t['id'] as String];
        expect(tables.take(old.length).toList(), old.keys.toList(), reason: '${tpl.id}: tables');
        for (final e in old.entries) {
          final t = (tpl.spec['tables'] as List).cast<Map>().firstWhere((x) => x['id'] == e.key);
          final fields = (t['fields'] as List).cast<Map>();
          final was = (e.value as List).cast<List>();
          expect([for (final f in fields.take(was.length)) f['id']], [for (final f in was) f[0]], reason: '${tpl.id}.${e.key}: fields');
          for (final (i, f) in was.indexed) {
            final opts = (fields[i]['options'] as List?) ?? const [];
            expect(opts.take((f[1] as List).length).toList(), f[1], reason: '${tpl.id}.${e.key}.${f[0]}: options');
          }
          // New fields: customers may leave them out; the business's own (deposit, total, code) are manager-only.
          for (final f in fields.skip(was.length)) {
            if (t['access'] == 'add' && f['manager_only'] != true) expect(f['required'], isNot(true), reason: '${tpl.id}.${e.key}.${f['id']} must be optional');
          }
        }
      }
      final menu = [for (final r in restaurantTpl.rows['menu_items']!) [r['name'], r['price']]];
      final oldMenu = snap['_menu'] as List;
      expect(menu.take(oldMenu.length).toList(), oldMenu, reason: 'dishes and prices unchanged, in order');
    });

    test('limits: tables, pages, fields; payment never comes before the status', () {
      for (final tpl in appTemplates) {
        final s = AppSpec.fromJson(tpl.spec.cast<String, dynamic>());
        expect(s.tables.length, lessThanOrEqualTo(12));
        expect(s.pages.length, lessThanOrEqualTo(10));
        expect(s.tables.length, (tpl.spec['tables'] as List).length, reason: '${tpl.id}: no table dropped');
        expect(s.pages.length, (tpl.spec['pages'] as List).length, reason: '${tpl.id}: no page dropped');
        for (final t in s.tables) {
          expect(t.fields.length, lessThanOrEqualTo(20), reason: t.id);
          final st = statusOf(t);
          if (t.fields.any((f) => f.id == 'status')) expect(st?.id, 'status', reason: '${tpl.id}.${t.id}');
          // The first manager-only choice is the status (old code and tests rely on it).
          if (st != null) expect(t.fields.where((f) => f.type == 'choice' && f.managerOnly).first.id, st.id);
        }
        // Every block of the template survives the repair (none points at something missing).
        for (final p in s.pages) {
          final raw = (tpl.spec['pages'] as List).cast<Map>().firstWhere((x) => x['id'] == p.id);
          expect(p.blocks.length, (raw['blocks'] as List).length, reason: '${tpl.id}/${p.id}: ${p.blocks.map((b) => b.type)}');
        }
      }
    });

    test('bookings: the date, time, what is booked and the status are found in every template', () {
      final want = {'restaurant': ('reservations', 'table'), 'salon': ('appointments', 'stylist'), 'barber': ('appointments', 'barber'), 'clinic': ('appointments', 'doctor')};
      for (final tpl in appTemplates) {
        final s = AppSpec.fromJson(tpl.spec.cast<String, dynamic>());
        for (final t in s.tables) {
          final b = BookingShape.of(s, t);
          if (want[tpl.id]?.$1 == t.id) {
            expect(b, isNotNull, reason: '${tpl.id}.${t.id}');
            expect(b!.resourceField.id, want[tpl.id]!.$2);
            expect(b.dateField.id, 'date');
            expect(b.timeField.id, 'time');
            expect(b.statusField?.id, 'status');
          } else {
            expect(b, isNull, reason: '${tpl.id}.${t.id} is not a timed booking');
          }
        }
      }
    });

    test('restaurant: the flagship has everything a restaurant needs', () {
      final s = AppSpec.fromJson(restaurantTpl.spec.cast<String, dynamic>());
      expect(s.tables.map((t) => t.id), containsAll(['closures', 'vouchers', 'private_events', 'reviews']));
      expect(s.pages.map((p) => p.id), containsAll(['home', 'menu', 'order', 'book', 'private_dining', 'vouchers', 'contact']));
      expect(s.page('book')!.blocks.map((b) => b.type), ['hero', 'availability', 'form']);
      expect(s.page('home')!.blocks.map((b) => b.type), containsAll(['hero', 'features', 'list', 'testimonials', 'contact']));
      expect(s.page('menu')!.blocks.last.data['layout'], 'menu');
      expect(closuresOf(s)!.id, 'closures');
      final orders = s.table('orders')!;
      expect(orders.field('payment')!.managerOnly, isTrue);
      expect(orders.field('total')!.managerOnly, isTrue);
      expect(s.table('reservations')!.field('deposit')!.managerOnly, isTrue);
      expect(s.table('vouchers')!.field('code')!.managerOnly, isTrue);
      // Customers send these; they never see them listed.
      for (final id in ['orders', 'reservations', 'vouchers', 'private_events']) {
        expect(s.table(id)!.access.see, isFalse, reason: id);
        expect(s.table(id)!.access.add, isTrue, reason: id);
      }
      expect(s.table('reviews')!.access.add, isFalse, reason: 'the manager picks which reviews show');
    });
  });

  group('new blocks', () {
    AppSpec make(List<Object?> blocks, {bool manager = false}) => AppSpec.fromJson({
          'name': 'Test',
          'tables': [
            {'id': 'dishes', 'access': 'see', 'fields': [{'id': 'name'}, {'id': 'price', 'type': 'money'}, {'id': 'photo', 'type': 'image'}, {'id': 'popular', 'type': 'yesno'}]},
            {'id': 'reviews', 'access': 'see', 'fields': [{'id': 'name'}, {'id': 'quote', 'type': 'longtext'}, {'id': 'rating', 'type': 'number'}]},
            {'id': 'bookings', 'access': 'add', 'fields': [{'id': 'name'}, {'id': 'phone', 'type': 'phone'}, {'id': 'notes', 'type': 'longtext'}]},
            {'id': 'secret', 'access': 'none', 'fields': [{'id': 'name'}, {'id': 'photo', 'type': 'image'}, {'id': 'memo', 'type': 'longtext'}]},
          ],
          'pages': [
            {'id': 'home', 'manager': manager, 'blocks': blocks},
          ],
        });

    test('gallery, testimonials, contact, features and the menu layout survive; unknown ones are dropped', () {
      final s = make([
        {'type': 'features', 'items': ['Fresh: every day', {'title': 'Local', 'text': 'from nearby farms'}]},
        {'type': 'contact', 'title': 'Find us'},
        {'type': 'gallery', 'table': 'dishes', 'title': 'Food'},
        {'type': 'gallery', 'images': ['/files/abc.jpg']},
        {'type': 'reviews', 'table': 'reviews'},
        {'type': 'menu', 'table': 'dishes', 'layout': 'menu', 'only': 'popular'},
        {'type': 'weird'},
        {'type': 'sparkles', 'table': 'dishes'},
      ]);
      final blocks = s.page('home')!.blocks;
      expect(blocks.map((b) => b.type), ['features', 'contact', 'gallery', 'gallery', 'testimonials', 'list']);
      expect(blocks[0].data['text'], 'Fresh: every day\nLocal: from nearby farms');
      expect(blocks[2].table, 'dishes');
      expect(blocks[3].data['images'], ['/files/abc.jpg']);
      expect(blocks[5].data['layout'], 'menu');
      expect(blocks[5].data['only'], 'popular');
      expect(blocks.map((b) => b.describe(s)), everyElement(isNot(contains('?'))));
      // Round trip.
      expect(AppSpec.fromJson(jsonDecode(jsonEncode(s.toJson()))).toJson(), s.toJson());
    });

    test('customers never see private tables through the new blocks', () {
      final s = make([
        {'type': 'testimonials', 'table': 'bookings'}, // people's notes: not public
        {'type': 'testimonials', 'table': 'secret'},
        {'type': 'gallery', 'table': 'secret'}, // and nothing else to show: dropped
        {'type': 'gallery', 'table': 'secret', 'images': ['/files/x.jpg']}, // keeps its own pictures only
        {'type': 'list', 'table': 'dishes', 'only': 'price'}, // not a yes/no: ignored
        {'type': 'features'}, // nothing in it
      ]);
      final blocks = s.page('home')!.blocks;
      expect(blocks.map((b) => b.type), ['gallery', 'list']);
      expect(blocks[0].table, isNull);
      expect(blocks[1].data.containsKey('only'), isFalse);
      // The manager's own pages may show them.
      final m = make([{'type': 'gallery', 'table': 'secret'}], manager: true);
      expect(m.page('home')!.blocks.single.table, 'secret');
    });
  });

  group('running restaurant', () {
    late Directory tmp;
    late Db db;
    late AppData data;
    late AppServer srv;
    late String base;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('pro');
      db = await Db.open(path: '${tmp.path}/t.db');
      final spec = AppSpec.fromJson(restaurantTpl.spec.cast<String, dynamic>());
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insert('apps', {'name': 'x', 'request': 'x', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': pin, 'created_at': now, 'updated_at': now});
      data = AppData(db, id, spec);
      for (final t in ['menu_items', 'dining_tables', 'opening_hours', 'reviews']) {
        for (final r in restaurantTpl.rows[t]!) {
          await data.add(t, r.cast<String, dynamic>(), manager: true);
        }
      }
      srv = AppServer(data: data, pin: pin, toolKey: key);
      await srv.start(0);
      base = 'http://127.0.0.1:${srv.port}';
    });

    tearDown(() async {
      await srv.stop();
      await db.raw.close();
      tmp.deleteSync(recursive: true);
    });

    Future<http.Response> post(String table, Map<String, Object?> body, {bool manager = false}) =>
        http.post(Uri.parse('$base/api/t/$table'), headers: {'X-Key': manager ? pin : '', 'Content-Type': 'application/json'}, body: jsonEncode(body));
    Future<McpSession> tools() async {
      final s = McpSession(HttpTransport('$base/mcp', headers: {'X-Tool-Key': key}));
      await s.initialize();
      return s;
    }

    test('the website: every page opens, and the new parts are drawn', () async {
      for (final p in ['/', '/manage', for (final p in data.spec.pages) '/p/${p.id}']) {
        expect((await http.get(Uri.parse('$base$p'))).statusCode, 200, reason: p);
      }
      final js = (await http.get(Uri.parse('$base/app.js'))).body;
      for (final f in ['function menuBlock', 'function galleryBlock', 'function testimonialsBlock', 'function contactBlock', 'function featuresBlock', 'function bars', 'function boardView', 'function customers', 'function record', 'function exportCsv', 'nowline', 'openstreetmap.org', 'delivery_fee', 'min_order']) {
        expect(js, contains(f));
      }
      expect((await http.get(Uri.parse('$base/app.css'))).body, contains('.mbar'));
      // Visitors see the reviews and the closed days; never anyone's booking.
      expect((await http.get(Uri.parse('$base/api/t/reviews'))).statusCode, 200);
      expect((await http.get(Uri.parse('$base/api/t/closures'))).statusCode, 200);
      for (final t in ['orders', 'reservations', 'vouchers', 'private_events']) {
        expect((await http.get(Uri.parse('$base/api/t/$t'))).statusCode, 403, reason: t);
      }
    });

    test('dashboard numbers: manager only, and right', () async {
      final none = await http.get(Uri.parse('$base/api/_stats'), headers: {'X-Key': ''});
      expect(none.statusCode, 403);
      expect(none.body, isNot(contains('revenue')));
      expect((await http.get(Uri.parse('$base/api/_stats'), headers: {'X-Key': '000000'})).statusCode, 403);
      final today = ymd(DateTime.now());
      expect((await post('orders', {'name': 'Ann Lee', 'phone': '07700 900001', 'type': 'Collection', 'items': [{'id': 'Margherita', 'qty': 2}]})).statusCode, 200); // 21
      expect((await post('orders', {'name': 'Bo Chen', 'phone': '07700 900002', 'type': 'Collection', 'items': [{'id': 'Diavola', 'qty': 1}]})).statusCode, 200); // 13
      final c = await post('orders', {'name': 'Cy Ali', 'phone': '07700 900003', 'type': 'Collection', 'items': [{'id': 'Tiramisù', 'qty': 1}]}); // cancelled below
      expect((await post('reservations', {'name': 'Di Rossi', 'phone': '07700 900004', 'date': today, 'time': '19:00', 'guests': 2})).statusCode, 200);
      expect((await post('reservations', {'name': 'Ed Walsh', 'phone': '07700 900005', 'date': ymd(DateTime.now().add(const Duration(days: 2))), 'time': '19:00', 'guests': 2})).statusCode, 200);
      await data.update('orders', (jsonDecode(c.body) as Map)['id'] as int, {'status': 'Cancelled'});
      final r = await http.get(Uri.parse('$base/api/_stats'), headers: {'X-Key': pin});
      expect(r.statusCode, 200);
      final s = jsonDecode(r.body) as Map;
      expect(s['bookings_today'], 1);
      expect(s['open_orders'], 2);
      expect(s['revenue_today'], 34);
      expect(s['revenue_7d'], 34);
      expect(s['new_today'], 5);
      expect((s['days'] as List).length, 14);
      expect((s['days'] as List).last, today);
      expect(s['tables']['orders']['counts'].last, 3);
      expect(s['tables']['reservations']['counts'].last, 2);
      expect((s['hours'] as List).length, 24);
      expect(s['hours'][19], 2, reason: 'both bookings are at 19:00');
    });

    test('a closed day refuses bookings on the website and by phone, and the plans show it', () async {
      final day = ymd(DateTime.now().add(const Duration(days: 9)));
      final next = ymd(DateTime.now().add(const Duration(days: 10)));
      await data.add('closures', {'reason': 'Private party', 'date': day, 'until': next}, manager: true);
      expect(await data.closedOn(day), 'Private party');
      expect(await data.closedOn(next), 'Private party');
      expect(await data.closedOn(ymd(DateTime.now().add(const Duration(days: 11)))), isNull);
      final web = await post('reservations', {'name': 'Fay Doe', 'phone': '07700 900010', 'date': next, 'time': '19:00', 'guests': 2});
      expect(web.statusCode, 400);
      expect(web.body, contains('closed'));
      expect(web.body, contains('Private party'));
      final event = await post('private_events', {'name': 'Gus Hart', 'phone': '07700 900011', 'date': day, 'guests': 20, 'event_type': 'Birthday'});
      expect(event.statusCode, 400);
      final s = await tools();
      final check = await s.callTool('check_reservations', {'date': day, 'time': '19:00', 'guests': 2});
      expect(check.text, contains('closed'));
      expect(check.text, isNot(contains('Free tables')));
      final add = await s.callTool('add_reservations', {'name': 'Hal Moss', 'phone': '07700 900012', 'date': day, 'time': '19:00', 'guests': 2});
      expect(add.isError, isTrue);
      expect(add.text, contains('closed'));
      final plan = jsonDecode((await http.get(Uri.parse('$base/api/_plan/reservations?date=$day'))).body) as Map;
      expect(plan['closed'], 'Private party');
      // The day after is open again; a booking can't be moved onto the closed day.
      final ok = await s.callTool('add_reservations', {'name': 'Ivy Bell', 'phone': '07700 900013', 'date': ymd(DateTime.now().add(const Duration(days: 11))), 'time': '19:00', 'guests': 2});
      expect(ok.isError, isFalse, reason: ok.text);
      final moved = await s.callTool('change_my_reservations', {'phone': '07700 900013', 'name': 'Ivy Bell', 'date': day});
      expect(moved.isError, isTrue);
      expect(moved.text, contains('closed'));
      expect(await data.nearestFree(BookingShape.of(data.spec, data.spec.table('reservations')!)!, day, '19:00'), isEmpty);
    });

    test('delivery: the fee is in the total, a delivery below the minimum is refused (website and phone)', () async {
      data.spec = data.spec.copyWith(site: {...data.spec.site, 'delivery_fee': '2.50', 'min_order': '£15'});
      final small = {'name': 'Jo Park', 'phone': '07700 900020', 'type': 'Delivery', 'address': '1 Elm Grove', 'postcode': 'N7 8QJ', 'items': [{'id': 'Tiramisù', 'qty': 1}]};
      final web = await post('orders', small);
      expect(web.statusCode, 400);
      expect(web.body, contains('minimum order for delivery is £15'));
      final s = await tools();
      final phone = await s.callTool('add_orders', small);
      expect(phone.isError, isTrue);
      expect(phone.text, contains('minimum'));
      // Collection has no minimum and no fee.
      final collect = await post('orders', {...small, 'type': 'Collection'});
      expect(collect.statusCode, 200, reason: collect.body);
      final big = await s.callTool('add_orders', {...small, 'phone': '07700 900021', 'name': 'Kim Long', 'items': [{'item': 'Diavola', 'qty': 2}]});
      expect(big.isError, isFalse, reason: big.text);
      expect(big.text, contains('Total: £28.50 (£26 + £2.50 delivery)'));
      final rows = await data.list('orders', manager: true);
      final kim = rows.firstWhere((r) => r['name'] == 'Kim Long');
      expect(kim['total'], 28.5, reason: 'the total is kept with the order');
      expect(kim['payment'], 'Unpaid');
      expect(rows.firstWhere((r) => r['name'] == 'Jo Park')['total'], 7);
      final t = await data.orderTotal('orders', kim);
      expect((t!.items, t.fee, t.total), (26, 2.5, 28.5));
      // The manager adds an item: the total follows.
      await data.update('orders', kim['id'] as int, {'items': [{'id': 'Diavola', 'qty': 3}]});
      expect((await data.get('orders', kim['id'] as int, manager: true))!['total'], 41.5);
    });

    test('customers can\'t set the status, payment, total or a voucher code', () async {
      final r = await post('orders', {'name': 'Lou Grant', 'phone': '07700 900030', 'type': 'Collection', 'items': [{'id': 'Margherita', 'qty': 1}], 'status': 'Done', 'payment': 'Paid card', 'total': 0});
      expect(r.statusCode, 200, reason: r.body);
      final row = (await data.get('orders', (jsonDecode(r.body) as Map)['id'] as int, manager: true))!;
      expect(row['status'], 'New');
      expect(row['payment'], 'Unpaid');
      expect(row['total'], 10.5);
      final v = await post('vouchers', {'name': 'May Fox', 'phone': '07700 900031', 'amount': 50, 'code': 'FREE100', 'status': 'Paid'});
      expect(v.statusCode, 200, reason: v.body);
      final vr = (await data.get('vouchers', (jsonDecode(v.body) as Map)['id'] as int, manager: true))!;
      expect(vr['code'], isNull);
      expect(vr['status'], 'Requested');
      // And can't change one either.
      final id = (jsonDecode(r.body) as Map)['id'];
      expect((await http.put(Uri.parse('$base/api/t/orders/$id'), headers: {'X-Key': ''}, body: jsonEncode({'status': 'Done'}))).statusCode, 403);
      final s = await tools();
      final changed = await s.callTool('change_my_orders', {'phone': '07700 900030', 'name': 'Lou Grant', 'status': 'Done', 'payment': 'Paid cash'});
      expect(changed.isError, isFalse, reason: changed.text);
      final after = (await data.get('orders', id as int, manager: true))!;
      expect(after['status'], 'New');
      expect(after['payment'], 'Unpaid');
    });

    test('a dish marked not available today can\'t be ordered', () async {
      final focaccia = (await data.list('menu_items', manager: true)).firstWhere((r) => r['name'] == 'Garlic focaccia');
      await data.update('menu_items', focaccia['id'] as int, {'available': false});
      final r = await post('orders', {'name': 'Ned Kay', 'phone': '07700 900040', 'type': 'Collection', 'items': [{'id': 'Garlic focaccia', 'qty': 1}]});
      expect(r.statusCode, 400);
      expect(r.body, contains('not available'));
    });

    test('the manager\'s page texts: highlights and gallery pictures can be edited, nothing unsafe kept', () async {
      final home = data.spec.page('home')!;
      final fi = home.blocks.indexWhere((b) => b.type == 'features');
      final pd = data.spec.page('private_dining')!;
      final gi = pd.blocks.indexWhere((b) => b.type == 'gallery');
      final r = await http.put(Uri.parse('$base/api/_site'), headers: {'X-Key': pin}, body: jsonEncode({
        'site': {'delivery_fee': '3', 'min_order': '20'},
        'pages': {
          'home': {'blocks': {'$fi': {'title': 'Why us', 'text': 'Fast: very\nKind: always'}}},
          'private_dining': {'blocks': {'$gi': {'images': ['/files/abc123.jpg', 'javascript:alert(1)', 'https://example.com/a.jpg']}}},
        },
      }));
      expect(r.statusCode, 200, reason: r.body);
      expect(data.spec.site['delivery_fee'], '3');
      expect(data.spec.site['min_order'], '20');
      expect(data.spec.page('home')!.blocks[fi].data['text'], 'Fast: very\nKind: always');
      expect(data.spec.page('private_dining')!.blocks[gi].data['images'], ['/files/abc123.jpg', 'https://example.com/a.jpg']);
      expect((await http.put(Uri.parse('$base/api/_site'), headers: {'X-Key': ''}, body: '{}')).statusCode, 403);
    });
  });

  test('an app made from an older template gets the new tables, rows and pages, and keeps its data', () async {
    final tmp = Directory.systemTemp.createTempSync('upgrade');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    final t = appTemplates.firstWhere((t) => t.id == 'restaurant');
    final id = await apps.createFromTemplate(t, ava: false, name: 'Pasargad');
    // As it was made before: no vouchers, closed days, reviews or private dining; a plain home page.
    final a = (await apps.app(id))!;
    final old = a.spec.toJson();
    const added = {'closures', 'vouchers', 'private_events', 'reviews'};
    old['tables'] = [for (final x in old['tables'] as List) if (!added.contains((x as Map)['id'])) x];
    old['pages'] = [
      for (final p in old['pages'] as List)
        if (!{'private', 'vouchers', 'contact', 'menu'}.contains((p as Map)['id'])) p['id'] == 'home' ? {...p, 'blocks': (p['blocks'] as List).take(2).toList()} : p,
    ];
    await apps.saveSpec(id, AppSpec.fromJson(old.cast<String, dynamic>()));
    final data = AppData(db, id, (await apps.app(id))!.spec);
    final day = DateTime.now().add(const Duration(days: 2)).toIso8601String().substring(0, 10);
    final mine = await data.add('reservations', {'name': 'Kept Booking', 'phone': '07700 900321', 'date': day, 'time': '19:00', 'guests': 2});

    expect(await apps.upgradeFromTemplate(id, t), isTrue);
    final spec = (await apps.app(id))!.spec;
    expect(spec.tables.map((t) => t.id), containsAll(added));
    expect(spec.pages.length, (t.spec['pages'] as List).length);
    expect(spec.pages.firstWhere((p) => p.id == 'home').blocks.length, ((t.spec['pages'] as List).first['blocks'] as List).length);
    final fresh = AppData(db, id, spec);
    expect(await fresh.list('reviews', manager: true), isNotEmpty, reason: 'sample reviews added');
    expect((await fresh.get('reservations', mine, manager: true))!['name'], 'Kept Booking');
    expect(spec.name, 'Pasargad');
    // Nothing more to do the second time.
    expect(await apps.upgradeFromTemplate(id, t), isFalse);
  });
}
