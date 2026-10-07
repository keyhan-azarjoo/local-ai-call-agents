/// The ready-made apps, second round: every template as a professional product for its sector.
/// Places left (classes, courses, events), stock that counts down, the hotel's room finder and
/// rooms by night, calendars, takings by service and no-shows, and that nothing made before changed.
///   flutter test test/app_pro2_test.dart
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
import 'package:localailine/services/mcp/mcp_client.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';

const key = 'pro2-test-tool-key-0123456789abcdefghij';
const pin = '135790';

/// Every table, field and choice of the templates after the first round (ids and options, in order),
/// their pages, and the sample records' names and prices. Apps made from them must keep working.
const phase1 = r'''{"restaurant":{"tables":{"menu_items":[["name",[]],["category",["Starters","Pizza","Pasta","Desserts","Drinks","Sides"]],["description",[]],["price",[]],["photo",[]],["vegetarian",[]],["spicy",[]],["allergens",[]],["vegan",[]],["gluten_free",[]],["popular",[]],["available",[]]],"dining_tables":[["number",[]],["seats",[]],["area",["Inside","Terrace","Window"]]],"orders":[["name",[]],["phone",[]],["type",["Collection","Delivery","Dine-in"]],["address",[]],["postcode",[]],["table",[]],["ready_at",[]],["items",[]],["notes",[]],["status",["New","Preparing","Ready","Out for delivery","Done","Cancelled"]],["payment",["Unpaid","Paid card","Paid cash"]],["total",[]]],"reservations":[["name",[]],["phone",[]],["date",[]],["time",[]],["guests",[]],["table",[]],["requests",[]],["status",["Confirmed","Seated","Finished","Cancelled","No-show"]],["occasion",["Birthday","Anniversary","Business","Date night","Other"]],["deposit",[]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]],"closures":[["reason",[]],["date",[]],["until",[]]],"vouchers":[["name",[]],["phone",[]],["amount",[]],["recipient",[]],["message",[]],["code",[]],["status",["Requested","Paid","Sent","Redeemed","Cancelled"]]],"private_events":[["name",[]],["phone",[]],["date",[]],["guests",[]],["event_type",["Birthday","Corporate","Wedding","Anniversary","Other"]],["notes",[]],["status",["Enquiry","Confirmed","Deposit paid","Cancelled"]]],"reviews":[["name",[]],["rating",[]],["quote",[]],["source",[]]]},"pages":["home","menu","order","book","private_dining","vouchers","contact"],"rows":{"menu_items":[["Burrata & heritage tomatoes",9.5],["Fritto misto",11],["Margherita",10.5],["Diavola",13],["Tartufo",15],["Cacio e pepe",12.5],["Linguine allo scoglio",18],["Tiramisù",7],["Limoncello sorbet",6],["Aperol spritz",9],["San Pellegrino",4],["Garlic focaccia",5],["Rocket & parmesan salad",5.5],["Rosemary potatoes",4.5]],"dining_tables":[["1",null],["2",null],["3",null],["4",null],["5",null],["6",null],["7",null]],"opening_hours":[["12:00",null]],"closures":[["Christmas",null],["New Year’s Day",null]],"reviews":[["Sophie M.",null],["James O.",null],["Priya K.",null]]}},"salon":{"tables":{"services":[["name",[]],["category",["Cut & style","Colour","Treatments","Nails"]],["description",[]],["duration",[]],["price",[]],["photo",[]]],"stylists":[["name",[]],["role",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["service",[]],["stylist",[]],["date",[]],["time",[]],["notes",[]],["status",["Confirmed","Done","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"pages":["home","team","book"],"rows":{"services":[["Women’s cut & blow-dry",58],["Men’s cut",32],["Blow-dry",35],["Full head colour",95],["Balayage",160],["Olaplex treatment",30],["Gel manicure",28]],"stylists":[["Amélie",null],["Marcus",null],["Priya",null]],"opening_hours":[["09:00",null]]}},"barber":{"tables":{"services":[["name",[]],["category",["Haircuts","Beard","Shaves","Kids"]],["description",[]],["duration",[]],["price",[]]],"barbers":[["name",[]],["speciality",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["service",[]],["barber",[]],["date",[]],["time",[]],["notes",[]],["status",["Booked","Done","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"pages":["home","team","book"],"rows":{"services":[["Skin fade",22],["Classic cut",18],["Buzz cut",12],["Beard trim",10],["Cut & beard",28],["Hot towel shave",20],["Kids cut",12]],"barbers":[["Tony",null],["Jay",null],["Ali",null]],"opening_hours":[["09:00",null]]}},"gym":{"tables":{"classes":[["name",[]],["day",["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]],["time",[]],["level",["All levels","Beginner","Advanced"]],["trainer",[]],["description",[]],["spots",[]],["photo",[]]],"trainers":[["name",[]],["speciality",[]],["bio",[]],["photo",[]]],"memberships":[["name",[]],["description",[]],["price",[]]],"signups":[["name",[]],["phone",[]],["email",[]],["class",[]],["date",[]],["status",["Booked","Attended","No-show","Cancelled"]]]},"pages":["home","classes","trainers"],"rows":{"trainers":[["Jade",null],["Tom",null],["Sofia",null]],"classes":[["Barbell strength",null],["HIIT blast",null],["Mobility flow",null],["Olympic lifting",null],["Saturday sweat",null]],"memberships":[["Off-peak",25],["Unlimited",45],["Class pass",80]]}},"shop":{"tables":{"products":[["name",[]],["category",["Bakery","Fresh","Pantry","Drinks","Household"]],["description",[]],["price",[]],["photo",[]],["in_stock",[]]],"orders":[["name",[]],["phone",[]],["items",[]],["type",["Collection","Delivery"]],["address",[]],["postcode",[]],["pickup",[]],["notes",[]],["status",["New","Packing","Ready","Out for delivery","Collected","Delivered","Cancelled"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"pages":["home","order"],"rows":{"products":[["Sourdough loaf",4.2],["Butter croissant",1.8],["Free-range eggs (6)",2.6],["Seasonal veg box",14],["Extra-virgin olive oil",8.5],["Ground coffee",6.4],["Sparkling lemonade",2.9],["Eco washing-up liquid",3.2]],"opening_hours":[["07:00",null]]}},"clinic":{"tables":{"treatments":[["name",[]],["description",[]],["duration",[]],["price",[]]],"doctors":[["name",[]],["role",[]],["bio",[]],["photo",[]]],"appointments":[["name",[]],["phone",[]],["email",[]],["treatment",[]],["doctor",[]],["date",[]],["time",[]],["reason",[]],["status",["Confirmed","Completed","Cancelled","No-show"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"pages":["home","team","book"],"rows":{"treatments":[["Check-up & clean",65],["Teeth whitening",299],["White filling",120],["Invisalign consultation",0],["Emergency appointment",85]],"doctors":[["Dr Hannah Reid",null],["Dr Omar Khalil",null],["Leah Grant",null]],"opening_hours":[["08:30",null]]}},"hotel":{"tables":{"rooms":[["name",[]],["description",[]],["guests",[]],["bed",["Double","King","Twin","Family"]],["price",[]],["sea_view",[]],["photo",[]]],"bookings":[["name",[]],["phone",[]],["email",[]],["room",[]],["check_in",[]],["check_out",[]],["guests",[]],["requests",[]],["status",["Requested","Confirmed","Checked in","Cancelled"]]]},"pages":["home","book"],"rows":{"rooms":[["Harbour View",165],["The Loft",145],["Garden Twin",115],["Family Suite",210]]}},"garage":{"tables":{"services":[["name",[]],["description",[]],["price",[]],["time",[]]],"bookings":[["name",[]],["phone",[]],["car",[]],["plate",[]],["services",[]],["date",[]],["notes",[]],["status",["Booked","In the workshop","Ready","Collected","Cancelled"]]],"opening_hours":[["opens",[]],["closes",[]],["days",[]]]},"pages":["home","book"],"rows":{"services":[["MOT test",54.85],["Interim service",129],["Full service",229],["Brake pads (front)",140],["Air-con re-gas",69],["Diagnostics",45]],"opening_hours":[["08:00",null]]}},"tutoring":{"tables":{"courses":[["name",[]],["subject",["Maths","English","Science","Languages","Coding"]],["level",["Primary","GCSE","A-level","Adults"]],["schedule",[]],["description",[]],["price",[]],["photo",[]]],"enrolments":[["student",[]],["parent",[]],["phone",[]],["email",[]],["course",[]],["notes",[]],["status",["New","Confirmed","Waiting list","Cancelled"]]]},"pages":["home","enrol"],"rows":{"courses":[["GCSE Maths booster",180],["A-level Chemistry",220],["Reading confidence",150],["Python for beginners",200],["Conversational Spanish",160]]}},"events":{"tables":{"events":[["name",[]],["date",[]],["time",[]],["genre",["Rock","Jazz","Electronic","Comedy","Folk"]],["description",[]],["price",[]],["photo",[]],["sold_out",[]]],"tickets":[["name",[]],["phone",[]],["email",[]],["event",[]],["quantity",[]],["status",["Requested","Paid","Sent","Cancelled"]]]},"pages":["home","tickets"],"rows":{"events":[["The Midnight Owls",12],["Late Jazz Session",8],["Deep House Friday",15],["Stand-up Showcase",10]]}},"realestate":{"tables":{"listings":[["title",[]],["type",["Sale","Rent"]],["price",[]],["bedrooms",[]],["area",[]],["description",[]],["photo",[]],["available",[]]],"viewings":[["name",[]],["phone",[]],["email",[]],["property",[]],["date",[]],["message",[]],["status",["New","Booked","Viewed","Offer made","Closed"]]]},"pages":["home","viewing"],"rows":{"listings":[["Victorian terrace, Jericho",685000],["Modern flat with balcony",1650],["Cottage with orchard",520000],["Studio near the station",975]]}}}''';

/// The home pages as the first round of most templates made them (block types), for the upgrade test.
const oldHomes = {
  'salon': ['hero', 'list', 'info'], 'barber': ['hero', 'list', 'info'], 'gym': ['hero', 'list'], 'shop': ['hero', 'list', 'info'], 'clinic': ['hero', 'list', 'info'],
  'hotel': ['hero', 'text', 'list'], 'garage': ['hero', 'list', 'info'], 'tutoring': ['hero', 'list'], 'events': ['hero', 'list'], 'realestate': ['hero', 'list'],
};

String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
AppTemplate tpl(String id) => appTemplates.firstWhere((t) => t.id == id);
AppSpec specOf(String id) => AppSpec.fromJson(tpl(id).spec.cast<String, dynamic>());

/// One template running on its own: its sample records (no closed days, so nothing depends on the date).
class Running {
  Running(this.db, this.data, this.srv, this.tmp);
  final Db db;
  final AppData data;
  final AppServer srv;
  final Directory tmp;
  String get base => 'http://127.0.0.1:${srv.port}';

  static Future<Running> start(String id) async {
    final tmp = Directory.systemTemp.createTempSync('pro2');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final spec = specOf(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final appId = await db.insert('apps', {'name': 'x', 'request': 'x', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': pin, 'created_at': now, 'updated_at': now});
    final data = AppData(db, appId, spec);
    for (final e in tpl(id).rows.entries) {
      if (e.key == 'closures') continue;
      for (final r in e.value) {
        await data.add(e.key, r.cast<String, dynamic>(), manager: true);
      }
    }
    final srv = AppServer(data: data, pin: pin, toolKey: key);
    await srv.start(0);
    return Running(db, data, srv, tmp);
  }

  Future<void> stop() async {
    await srv.stop();
    await db.raw.close();
    tmp.deleteSync(recursive: true);
  }

  Future<http.Response> get(String path, {bool manager = false}) => http.get(Uri.parse('$base$path'), headers: {if (manager) 'X-Key': pin});
  Future<http.Response> post(String table, Map<String, Object?> body) =>
      http.post(Uri.parse('$base/api/t/$table'), headers: {'X-Key': '', 'Content-Type': 'application/json'}, body: jsonEncode(body));
  Future<McpSession> tools() async {
    final s = McpSession(HttpTransport('$base/mcp', headers: {'X-Tool-Key': key}));
    await s.initialize();
    return s;
  }

  Future<Map<String, Object?>> row(String table, String name) async {
    final t = data.spec.table(table)!;
    return (await data.list(table, manager: true)).firstWhere((r) => r[t.labelField] == name);
  }
}

/// The coming [weekday] (1 = Monday), today included.
String next(int weekday) {
  final now = DateTime.now();
  var k = 0;
  while (DateTime(now.year, now.month, now.day + k).weekday != weekday) {
    k++;
  }
  return ymd(DateTime(now.year, now.month, now.day + k));
}

void main() {
  group('templates', () {
    test('every table, field and choice from before keeps its id and place; samples keep their names and prices', () {
      final snap = jsonDecode(phase1) as Map<String, dynamic>;
      for (final t in appTemplates) {
        final old = snap[t.id] as Map<String, dynamic>;
        final tables = (t.spec['tables'] as List).cast<Map>();
        final oldTables = (old['tables'] as Map).cast<String, dynamic>();
        expect([for (final x in tables.take(oldTables.length)) x['id']], oldTables.keys.toList(), reason: '${t.id}: tables in order');
        for (final e in oldTables.entries) {
          final fields = (tables.firstWhere((x) => x['id'] == e.key)['fields'] as List).cast<Map>();
          final was = (e.value as List).cast<List>();
          expect([for (final f in fields.take(was.length)) f['id']], [for (final f in was) f[0]], reason: '${t.id}.${e.key}: fields');
          for (final (i, f) in was.indexed) {
            expect(((fields[i]['options'] as List?) ?? const []).take((f[1] as List).length).toList(), f[1], reason: '${t.id}.${e.key}.${f[0]}: options');
          }
          final table = tables.firstWhere((x) => x['id'] == e.key);
          for (final f in fields.skip(was.length)) {
            // New: optional for customers; the business's own figures and notes are the manager's.
            if (table['access'] == 'add' && f['manager_only'] != true) expect(f['required'], isNot(true), reason: '${t.id}.${e.key}.${f['id']}');
            if (RegExp(r'^(deposit|total|quote|code|stock_qty|capacity|sku|job_notes|medical_notes|payment)$').hasMatch('${f['id']}')) {
              expect(f['manager_only'], isTrue, reason: '${t.id}.${e.key}.${f['id']} is the manager\'s');
            }
          }
        }
        final pages = [for (final p in (t.spec['pages'] as List).cast<Map>()) p['id']];
        expect(pages, containsAll(old['pages'] as List), reason: '${t.id}: pages kept');
        for (final e in (old['rows'] as Map).entries) {
          final rows = t.rows[e.key]!;
          final table = (t.spec['tables'] as List).cast<Map>().firstWhere((x) => x['id'] == e.key);
          final first = ((table['fields'] as List).first as Map)['id'];
          expect([for (final r in rows.take((e.value as List).length)) [r[first], r['price']]], e.value, reason: '${t.id}.${e.key}: samples');
        }
      }
    });

    test('every template: a rich home page, reviews, a contact page, and within the limits', () {
      for (final t in appTemplates) {
        final s = specOf(t.id);
        expect(s.tables.length, lessThanOrEqualTo(12), reason: t.id);
        expect(s.pages.length, lessThanOrEqualTo(10), reason: t.id);
        for (final x in s.tables) {
          expect(x.fields.length, lessThanOrEqualTo(20), reason: '${t.id}.${x.id}');
          // Anything customers send has their name and number, so the phone tools find, change and cancel it.
          if (x.access.add && !x.single) {
            expect(x.fields.any((f) => f.type == 'phone' && f.id == 'phone'), isTrue, reason: '${t.id}.${x.id}');
            expect(statusOf(x)?.options.any((o) => o.contains('Cancel')), isTrue, reason: '${t.id}.${x.id}');
            expect(x.access.see, isFalse, reason: '${t.id}.${x.id}: customers never list it');
          }
        }
        final home = s.pages.first.blocks.map((b) => b.type).toList();
        expect(home, containsAll(['hero', 'features', 'list', 'testimonials', 'contact']), reason: '${t.id}: $home');
        expect(s.table('reviews')?.access.see, isTrue, reason: t.id);
        expect(s.table('reviews')?.access.add, isFalse, reason: '${t.id}: the manager picks the reviews');
        expect(s.page('contact')?.blocks.map((b) => b.type), contains('contact'), reason: t.id);
        expect(t.rows['reviews'], hasLength(greaterThanOrEqualTo(3)), reason: t.id);
        final raw = (t.spec['pages'] as List).cast<Map>();
        for (final p in s.pages) {
          expect(p.blocks.length, (raw.firstWhere((x) => x['id'] == p.id)['blocks'] as List).length, reason: '${t.id}/${p.id}: every block survives');
        }
      }
    });

    test('what each sector needs', () {
      for (final id in ['salon', 'barber', 'clinic']) {
        final s = specOf(id);
        expect(s.table('vouchers')!.access.add, isTrue, reason: id);
        expect(s.tables.any((t) => const {'packages', 'plans'}.contains(t.id) && t.access.see), isTrue, reason: id);
        expect(closuresOf(s)?.id, 'closures', reason: id);
        expect(s.table('appointments')!.field('status')!.options.last, 'No-show', reason: id);
      }
      final clinic = specOf('clinic');
      final appt = clinic.table('appointments')!;
      expect(appt.field('medical_notes')!.managerOnly, isTrue);
      expect(appt.field('nhs_private')!.options, ['NHS', 'Private']);
      expect(appt.field('new_patient')!.type, 'yesno');
      expect(clinic.page('faq')!.blocks.where((b) => b.type == 'text'), hasLength(3));
      expect(clinic.table('treatments')!.field('category')!.type, 'choice');

      final hotel = specOf('hotel');
      expect(AppData.stayOf(hotel.table('bookings')!), isNotNull);
      expect(hotel.page('book')!.blocks.map((b) => b.type), ['hero', 'stay', 'form']);
      expect(hotel.table('opening_hours')!.single, isTrue);
      expect(hotel.table('bookings')!.field('total')!.managerOnly, isTrue);
      expect(AppData.minNightsOf(hotel.table('rooms')!)?.id, 'min_nights');

      final shop = specOf('shop');
      expect(AppData.stockOf(shop.table('products')!)?.id, 'stock_qty');
      expect(shop.table('products')!.field('stock_qty')!.managerOnly, isTrue);
      expect(AppData.priceOf(shop.table('products')!)!.id, 'price', reason: 'the sale price is not the price');

      final garage = specOf('garage').table('bookings')!;
      expect(garage.field('quote')!.managerOnly, isTrue);
      expect(garage.field('courtesy_car')!.type, 'yesno');

      final homes = specOf('realestate');
      expect(homes.table('listings')!.field('status')!.managerOnly, isFalse);
      expect(homes.table('listings')!.field('status')!.options, containsAll(['For sale', 'Under offer', 'Sold', 'Let']));
      expect(homes.table('valuations')!.access.add, isTrue);

      final gym = specOf('gym');
      expect(gym.page('classes')!.blocks[1].data['layout'], 'timetable');
      expect(weekdayOf(gym.table('classes')!)?.id, 'day');
      expect(gym.table('joins')!.field('membership')!.link, 'memberships');
    });

    test('places: classes, courses and events have them; tables and stylists are booked by time instead', () async {
      final want = {'gym': {'signups': 'class'}, 'tutoring': {'enrolments': 'course'}, 'events': {'tickets': 'event'}};
      final db = await Db.open(path: '${Directory.systemTemp.createTempSync('places').path}/t.db');
      for (final t in appTemplates) {
        final s = specOf(t.id);
        final d = AppData(db, 0, s);
        for (final x in s.tables) {
          final links = d.placeLinks(x).map((f) => f.id).toList();
          expect(links, want[t.id]?[x.id] == null ? isEmpty : [want[t.id]![x.id]], reason: '${t.id}.${x.id}');
        }
      }
      await db.raw.close();
    });
  });

  group('new blocks', () {
    AppSpec make(List<Object?> blocks, {bool manager = false}) => AppSpec.fromJson({
          'name': 'Test',
          'tables': [
            {'id': 'rooms', 'access': 'see', 'fields': [{'id': 'name'}, {'id': 'price', 'type': 'money'}]},
            {'id': 'stays', 'access': 'add', 'fields': [{'id': 'name'}, {'id': 'phone', 'type': 'phone'}, {'id': 'room', 'type': 'link', 'link': 'rooms'}, {'id': 'arrive', 'type': 'date'}, {'id': 'leave', 'type': 'date'}]},
            {'id': 'notes', 'access': 'none', 'fields': [{'id': 'name'}, {'id': 'room', 'type': 'link', 'link': 'rooms'}, {'id': 'from', 'type': 'date'}, {'id': 'to', 'type': 'date'}]},
            {'id': 'classes', 'access': 'see', 'fields': [{'id': 'name'}, {'id': 'day', 'type': 'choice', 'options': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']}, {'id': 'time', 'type': 'time'}]},
            {'id': 'dishes', 'access': 'see', 'fields': [{'id': 'name'}, {'id': 'price', 'type': 'money'}]},
          ],
          'pages': [
            {'id': 'home', 'manager': manager, 'blocks': blocks},
          ],
        });

    test('the room finder and the timetable survive; where they don\'t fit they go', () {
      final s = make([
        {'type': 'stay', 'table': 'stays', 'title': 'Find a room'},
        {'type': 'availability', 'table': 'stays'}, // free times on a list of stays: the room finder
        {'type': 'room_finder', 'table': 'stay'},
        {'type': 'stay', 'table': 'dishes'}, // not stays
        {'type': 'stay', 'table': 'notes'}, // customers can't book these
        {'type': 'list', 'table': 'classes', 'layout': 'timetable'},
        {'type': 'list', 'table': 'dishes', 'layout': 'weekly'}, // no day of the week: a plain list
      ]);
      final blocks = s.page('home')!.blocks;
      expect(blocks.map((b) => b.type), ['stay', 'stay', 'stay', 'list', 'list']);
      expect(blocks.take(3).map((b) => b.table), everyElement('stays'));
      expect(blocks[0].data['title'], 'Find a room');
      expect(blocks[3].data['layout'], 'timetable');
      expect(blocks[4].data.containsKey('layout'), isFalse);
      expect(blocks.map((b) => b.describe(s)), everyElement(isNot(contains('?'))));
      expect(blocks[0].describe(s), contains('free rooms'));
      expect(blocks[3].describe(s), contains('timetable'));
      expect(AppSpec.fromJson(jsonDecode(jsonEncode(s.toJson()))).toJson(), s.toJson(), reason: 'round trip');
      // The manager's own pages may show a finder for any list of stays.
      expect(make([{'type': 'stay', 'table': 'notes'}], manager: true).page('home')!.blocks.single.table, 'notes');
      expect(isStayTable(s.table('stays')!), isTrue);
      expect(isStayTable(s.table('dishes')!), isFalse);
    });
  });

  group('places left', () {
    test('gym: a full class is refused on the website and by phone, per day; the website shows places left, never who', () async {
      final r = await Running.start('gym');
      try {
        final cls = await r.row('classes', 'Olympic lifting');
        await r.data.update('classes', cls['id'] as int, {'spots': 2});
        final day = next(DateTime.thursday);
        for (final (i, n) in ['Ada Stone', 'Ben Crane'].indexed) {
          final ok = await r.post('signups', {'name': n, 'phone': '07700 90010$i', 'class': 'Olympic lifting', 'date': day});
          expect(ok.statusCode, 200, reason: ok.body);
        }
        final full = await r.post('signups', {'name': 'Cal Dunn', 'phone': '07700 900103', 'class': 'Olympic lifting', 'date': day});
        expect(full.statusCode, 400);
        expect(full.body, contains('full'));
        final s = await r.tools();
        final phone = await s.callTool('add_signups', {'name': 'Dee Ford', 'phone': '07700 900104', 'class': 'Olympic lifting', 'date': day});
        expect(phone.isError, isTrue);
        expect(phone.text, contains('full'));
        // Another week has room.
        final later = ymd(DateTime.parse(day).add(const Duration(days: 7)));
        expect((await s.callTool('add_signups', {'name': 'Dee Ford', 'phone': '07700 900104', 'class': 'Olympic lifting', 'date': later})).isError, isFalse);
        final places = await r.get('/api/_places/classes');
        expect(places.statusCode, 200);
        final items = (jsonDecode(places.body) as Map)['items'] as Map;
        expect(items['${cls['id']}'], {'left': 0, 'capacity': 2, 'date': day});
        for (final secret in ['Ada', 'Ben', '900100', '900101']) {
          expect(places.body, isNot(contains(secret)));
        }
        // A cancellation frees a place.
        final ada = (await r.data.list('signups', manager: true)).firstWhere((x) => x['name'] == 'Ada Stone');
        expect((await s.callTool('cancel_my_signups', {'phone': '07700 900100', 'name': 'Ada Stone', 'id': ada['id']})).isError, isFalse);
        expect((await r.post('signups', {'name': 'Cal Dunn', 'phone': '07700 900103', 'class': 'Olympic lifting', 'date': day})).statusCode, 200);
        // The timetable and places are on the website.
        expect((jsonDecode((await r.get('/api/_spec')).body) as Map)['places'], ['classes']);
      } finally {
        await r.stop();
      }
    });

    test('events: tickets left, then sold out (website and phone); the total is kept', () async {
      final r = await Running.start('events');
      try {
        final ev = await r.row('events', 'Late Jazz Session');
        await r.data.update('events', ev['id'] as int, {'capacity': 5});
        final a = await r.post('tickets', {'name': 'Eve Hale', 'phone': '07700 900201', 'event': 'Late Jazz Session', 'quantity': 3});
        expect(a.statusCode, 200, reason: a.body);
        final b = await r.post('tickets', {'name': 'Fin Gray', 'phone': '07700 900202', 'event': 'Late Jazz Session', 'quantity': 3});
        expect(b.statusCode, 400);
        expect(b.body, contains('Only 2 tickets left'));
        final s = await r.tools();
        expect((await s.callTool('add_tickets', {'name': 'Fin Gray', 'phone': '07700 900202', 'event': 'Late Jazz Session', 'quantity': 2})).isError, isFalse);
        final out = await s.callTool('add_tickets', {'name': 'Gus Hill', 'phone': '07700 900203', 'event': 'Late Jazz Session', 'quantity': 1});
        expect(out.isError, isTrue);
        expect(out.text, contains('sold out'));
        final p = jsonDecode((await r.get('/api/_places/events')).body) as Map;
        expect(p['word'], 'tickets');
        expect((p['items'] as Map)['${ev['id']}']['left'], 0);
        expect((await r.get('/api/t/events')).body, isNot(contains('capacity')), reason: 'how many there are is the manager\'s');
        final eve = (await r.data.list('tickets', manager: true)).firstWhere((x) => x['name'] == 'Eve Hale');
        expect(eve['total'], 24, reason: '3 × £8');
        // Marked sold out by hand: refused too.
        final owls = await r.row('events', 'The Midnight Owls');
        await r.data.update('events', owls['id'] as int, {'sold_out': true});
        final sold = await r.post('tickets', {'name': 'Hal Ives', 'phone': '07700 900204', 'event': 'The Midnight Owls', 'quantity': 1});
        expect(sold.statusCode, 400);
        expect(sold.body, contains('sold out'));
      } finally {
        await r.stop();
      }
    });

    test('tutoring: a course with no places left is refused', () async {
      final r = await Running.start('tutoring');
      try {
        final c = await r.row('courses', 'A-level Chemistry');
        await r.data.update('courses', c['id'] as int, {'seats': 1});
        expect((await r.post('enrolments', {'student': 'Ivy Jones', 'phone': '07700 900301', 'course': 'A-level Chemistry'})).statusCode, 200);
        final s = await r.tools();
        final no = await s.callTool('add_enrolments', {'student': 'Jon King', 'phone': '07700 900302', 'course': 'A-level Chemistry'});
        expect(no.isError, isTrue);
        expect(no.text, contains('full'));
        expect((await s.callTool('add_enrolments', {'student': 'Jon King', 'phone': '07700 900302', 'course': 'GCSE Maths booster'})).isError, isFalse);
      } finally {
        await r.stop();
      }
    });
  });

  test('shop: stock counts down, more than is left is refused (website and phone), a cancelled order puts it back', () async {
    final r = await Running.start('shop');
    try {
      final loaf = await r.row('products', 'Sourdough loaf');
      final id = loaf['id'] as int;
      await r.data.update('products', id, {'stock_qty': 3});
      final pickup = '${ymd(DateTime.now().add(const Duration(days: 1)))} 10:00';
      Map<String, Object?> order(String name, String phone, int qty) => {'name': name, 'phone': phone, 'type': 'Collection', 'pickup': pickup, 'items': [{'id': 'Sourdough loaf', 'qty': qty}]};
      final first = await r.post('orders', order('Kay Lee', '07700 900401', 2));
      expect(first.statusCode, 200, reason: first.body);
      Future<num?> stock() async => (await r.data.get('products', id, manager: true))!['stock_qty'] as num?;
      expect(await stock(), 1);
      final tooMany = await r.post('orders', order('Lou Moss', '07700 900402', 2));
      expect(tooMany.statusCode, 400);
      expect(tooMany.body, contains('Only 1'));
      final s = await r.tools();
      final phone = await s.callTool('add_orders', order('Lou Moss', '07700 900402', 2));
      expect(phone.isError, isTrue);
      expect(phone.text, contains('Only 1'));
      expect((await s.callTool('add_orders', order('Lou Moss', '07700 900402', 1))).isError, isFalse);
      expect(await stock(), 0);
      expect((await r.data.get('products', id, manager: true))!['in_stock'], isFalse, reason: 'sold out shows on the website');
      final none = await r.post('orders', order('Max Nash', '07700 900403', 1));
      expect(none.statusCode, 400);
      expect(none.body, contains('out of stock'));
      // Cancelled: the two loaves go back.
      final kay = (jsonDecode(first.body) as Map)['id'] as int;
      await r.data.update('orders', kay, {'status': 'Cancelled'});
      expect(await stock(), 2);
      // Customers never see the count or the product code; the sale price is what is charged.
      final public = await r.get('/api/t/products');
      expect(public.body, isNot(contains('stock_qty')));
      expect(public.body, isNot(contains('BAK-001')));
      final honey = await r.post('orders', {...order('Ned Ode', '07700 900404', 1), 'items': [{'id': 'Wildflower honey', 'qty': 2}]});
      expect(honey.statusCode, 200, reason: honey.body);
      expect((await r.data.get('orders', (jsonDecode(honey.body) as Map)['id'] as int, manager: true))!['total'], 11.98);
    } finally {
      await r.stop();
    }
  });

  test('hotel: the room finder shows free rooms (never who), rooms by night is the manager\'s, minimum nights and the stay\'s total', () async {
    final r = await Running.start('hotel');
    try {
      final d0 = DateTime.now().add(const Duration(days: 40));
      String day(int n) => ymd(d0.add(Duration(days: n)));
      final s = await r.tools();
      final booked = await s.callTool('add_bookings', {'name': 'Olive Park', 'phone': '07700 900501', 'room': 'Harbour View', 'check_in': day(0), 'check_out': day(3), 'guests': 2});
      expect(booked.isError, isFalse, reason: booked.text);
      final harbour = await r.row('rooms', 'Harbour View');
      final mine = (await r.data.list('bookings', manager: true)).single;
      expect(mine['total'], 495, reason: '3 nights × £165');
      final stay = await r.get('/api/_stay/bookings?from=${day(1)}&to=${day(2)}&guests=2');
      expect(stay.statusCode, 200);
      final j = jsonDecode(stay.body) as Map;
      expect(j['nights'], 1);
      expect(j['free'], isNot(contains(harbour['id'])));
      expect((j['free'] as List).length, 3);
      for (final secret in ['Olive', 'Park', '900501']) {
        expect(stay.body, isNot(contains(secret)));
      }
      expect((jsonDecode((await r.get('/api/_stay/bookings?from=${day(3)}&to=${day(5)}')).body) as Map)['free'], contains(harbour['id']), reason: 'free from check-out day');
      expect((await r.get('/api/_stay/bookings?from=${day(3)}&to=${day(2)}')).statusCode, 400);
      // Rooms by night, with names: only the manager.
      final occ = await r.get('/api/_occupancy/bookings?from=${day(0)}');
      expect(occ.statusCode, 403);
      expect(occ.body, isNot(contains('Olive')));
      final m = await r.get('/api/_occupancy/bookings?from=${day(-2)}&days=7', manager: true);
      expect(m.statusCode, 200);
      final o = jsonDecode(m.body) as Map;
      expect((o['nights'] as List).length, 7);
      expect((o['rooms'] as List).length, 4);
      expect((o['stays'] as List).single['who'], 'Olive Park');
      // A room let for at least three nights: a two-night stay is refused, and the finder says why.
      final suite = await r.row('rooms', 'Family Suite');
      await r.data.update('rooms', suite['id'] as int, {'min_nights': 3});
      final short = await r.post('bookings', {'name': 'Pia Quinn', 'phone': '07700 900502', 'room': 'Family Suite', 'check_in': day(10), 'check_out': day(12), 'guests': 3});
      expect(short.statusCode, 400);
      expect(short.body, contains('at least 3 nights'));
      final f = jsonDecode((await r.get('/api/_stay/bookings?from=${day(10)}&to=${day(12)}')).body) as Map;
      expect(f['too_short'], {'${suite['id']}': 3});
      expect(f['free'], isNot(contains(suite['id'])));
      final check = await s.callTool('check_bookings', {'check_in': day(10), 'check_out': day(12), 'guests': 3});
      expect(check.text, contains('at least 3 nights'));
      expect((await r.post('bookings', {'name': 'Pia Quinn', 'phone': '07700 900502', 'room': 'Family Suite', 'check_in': day(10), 'check_out': day(13), 'guests': 3})).statusCode, 200);
      // A closed night: the finder says so.
      await r.data.add('closures', {'reason': 'Winter break', 'date': day(20)}, manager: true);
      final closed = jsonDecode((await r.get('/api/_stay/bookings?from=${day(19)}&to=${day(21)}')).body) as Map;
      expect(closed['closed'], 'Winter break');
      expect(closed['free'], isEmpty);
    } finally {
      await r.stop();
    }
  });

  test('real estate: a sold home can\'t be viewed; homes show their status', () async {
    final r = await Running.start('realestate');
    try {
      final home = await r.row('listings', 'Cottage with orchard');
      await r.data.update('listings', home['id'] as int, {'status': 'Sold'});
      final v = await r.post('viewings', {'name': 'Quin Rose', 'phone': '07700 900601', 'property': 'Cottage with orchard'});
      expect(v.statusCode, 400);
      expect(v.body, contains('sold'));
      expect((await r.post('viewings', {'name': 'Quin Rose', 'phone': '07700 900601', 'property': 'Studio near the station'})).statusCode, 200);
      expect((await r.get('/api/t/listings')).body, allOf(contains('To let'), contains('For sale'), contains('"epc":"B"')));
      final val = await r.post('valuations', {'name': 'Ros Sim', 'phone': '07700 900602', 'address': '9 Walton Street', 'purpose': 'Selling'});
      expect(val.statusCode, 200, reason: val.body);
      expect((await r.get('/api/t/valuations')).statusCode, 403);
    } finally {
      await r.stop();
    }
  });

  test('dashboard: takings by service and no-shows (manager only)', () async {
    final r = await Running.start('salon');
    try {
      final now = DateTime.now();
      String ago(int n) => ymd(DateTime(now.year, now.month, now.day - n));
      for (final (i, (svc, st)) in [('Balayage', 'Done'), ('Balayage', 'Done'), ('Blow-dry', 'No-show'), ('Gel manicure', 'Cancelled'), ('Men’s cut', 'Done')].indexed) {
        await r.data.add('appointments', {'name': 'Client $i', 'phone': '07700 90070$i', 'service': svc, 'date': ago(i + 1), 'time': '1$i:00', 'status': st}, manager: true);
      }
      // Long ago: not in the last 30 days.
      await r.data.add('appointments', {'name': 'Old Client', 'phone': '07700 900799', 'service': 'Balayage', 'date': ago(60), 'time': '10:00', 'status': 'No-show'}, manager: true);
      expect((await r.get('/api/_stats')).statusCode, 403);
      final s = jsonDecode((await r.get('/api/_stats', manager: true)).body) as Map;
      final by = s['by_service']['appointments'] as Map;
      expect(by['what'], 'Services');
      expect(by['items'].first, {'name': 'Balayage', 'count': 2, 'revenue': 320});
      expect([for (final x in by['items'] as List) x['name']], isNot(contains('Gel manicure')), reason: 'cancelled');
      expect(s['no_shows']['appointments'], {'title': 'Appointments', 'count': 1, 'of': 4, 'rate': 25.0});
    } finally {
      await r.stop();
    }
  });

  test('every page of every template opens, and the new parts are drawn', () async {
    for (final t in appTemplates) {
      final r = await Running.start(t.id);
      try {
        for (final p in ['/', '/manage', for (final p in r.data.spec.pages) '/p/${p.id}']) {
          expect((await r.get(p)).statusCode, 200, reason: '${t.id} $p');
        }
        // The manager-only endpoints answer no one else.
        expect((await r.get('/api/_stats')).statusCode, 403, reason: t.id);
        for (final x in r.data.spec.tables.where((x) => AppData.stayOf(x) != null)) {
          expect((await r.get('/api/_occupancy/${x.id}')).statusCode, 403, reason: t.id);
        }
        // Customers never list what people send.
        for (final x in r.data.spec.tables.where((x) => x.access.add && !x.single)) {
          expect((await r.get('/api/t/${x.id}')).statusCode, 403, reason: '${t.id}.${x.id}');
        }
      } finally {
        await r.stop();
      }
    }
    final r = await Running.start('restaurant');
    try {
      final js = (await r.get('/app.js')).body;
      for (final f in ['function stayBlock', 'function timetableBlock', 'function weekView', 'function monthView', 'function occupancyView', 'function placesBadge', 'function priceHtml', 'function chooseFor', 'no_shows', 'by_service', '_occupancy/', '_stay/', '_places/']) {
        expect(js, contains(f));
      }
      final css = (await r.get('/app.css')).body;
      for (final c in ['.tt-day', '.stay-grid', '.wk-b', '.cal-g', '.occ', '.svc-bar', '.dbadge.places']) {
        expect(css, contains(c));
      }
    } finally {
      await r.stop();
    }
  });

  test('an app made from an older template of each kind gets the new tables, pages and home page, and keeps its data', () async {
    final tmp = Directory.systemTemp.createTempSync('upgrade2');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    final snap = jsonDecode(phase1) as Map<String, dynamic>;
    try {
      for (final t in appTemplates.where((t) => t.id != 'restaurant')) {
        final id = await apps.createFromTemplate(t, ava: false);
        await apps.stop(id);
        final old = (snap[t.id] as Map)['tables'] as Map;
        final oldPages = ((snap[t.id] as Map)['pages'] as List).cast<String>();
        // As it was made in the first round: those tables and fields only, those pages, a plain home page.
        final raw = (await apps.app(id))!.spec.toJson();
        raw['tables'] = [
          for (final x in (raw['tables'] as List).cast<Map>())
            if (old.containsKey(x['id'])) {...x, 'fields': [for (final f in (x['fields'] as List).cast<Map>()) if ((old[x['id']] as List).any((o) => o[0] == f['id'])) f]},
        ];
        raw['pages'] = [
          for (final p in (raw['pages'] as List).cast<Map>())
            if (oldPages.contains(p['id']))
              p['id'] == 'home'
                  ? {
                      ...p,
                      'blocks': [
                        for (final type in oldHomes[t.id]!)
                          if (type == 'info') {'type': 'info', 'table': 'opening_hours'} else if (type == 'list') {'type': 'list', 'table': (p['blocks'] as List).cast<Map>().firstWhere((b) => b['type'] == 'list')['table']} else (p['blocks'] as List).cast<Map>().firstWhere((b) => b['type'] == type),
                      ],
                    }
                  : p,
        ];
        await apps.saveSpec(id, AppSpec.fromJson(raw.cast<String, dynamic>()));
        final before = (await apps.app(id))!.spec;
        expect(before.tables.length, old.length, reason: t.id);
        // A customer's booking or order, kept through the upgrade.
        final add = before.tables.firstWhere((x) => x.access.add && !x.single);
        final data = AppData(db, id, before);
        final values = <String, dynamic>{};
        for (final f in add.fields.where((f) => f.required && f.when == null)) {
          final lt = f.link == null ? null : before.table(f.link!);
          final first = lt == null ? null : (await data.list(lt.id, manager: true)).first[lt.labelField];
          values[f.id] = switch (f.type) {
            'phone' => '07700 900888',
            'date' => ymd(DateTime.now().add(const Duration(days: 50))),
            'time' => '11:00',
            'datetime' => '${ymd(DateTime.now().add(const Duration(days: 2)))} 10:00',
            'number' || 'money' => 2,
            'choice' => f.options.first,
            'link' => first,
            'links' => f.qty ? [{'id': first, 'qty': 1}] : [first],
            _ => 'Kept Customer',
          };
        }
        if (AppData.stayOf(add) != null) values['check_out'] = ymd(DateTime.now().add(const Duration(days: 52)));
        final kept = await data.add(add.id, values);

        expect(await apps.upgradeFromTemplate(id, t), isTrue, reason: t.id);
        final spec = (await apps.app(id))!.spec;
        expect(spec.tables.map((x) => x.id).toSet(), {for (final x in (t.spec['tables'] as List).cast<Map>()) x['id']}, reason: '${t.id}: every table');
        expect(spec.pages.map((p) => p.id).toSet(), {for (final p in (t.spec['pages'] as List).cast<Map>()) p['id']}, reason: '${t.id}: every page');
        expect(spec.pages.firstWhere((p) => p.id == 'home').blocks.map((b) => b.type), [for (final b in ((t.spec['pages'] as List).first['blocks'] as List).cast<Map>()) b['type']], reason: '${t.id}: the new home page');
        for (final x in (t.spec['tables'] as List).cast<Map>()) {
          expect(spec.table('${x['id']}')!.fields.map((f) => f.id).toList(), [for (final f in (x['fields'] as List).cast<Map>()) f['id']], reason: '${t.id}.${x['id']}: fields');
        }
        final fresh = AppData(db, id, spec);
        expect((await fresh.get(add.id, kept, manager: true))![add.labelField], 'Kept Customer', reason: '${t.id}: data kept');
        expect(await fresh.list('reviews', manager: true), isNotEmpty, reason: '${t.id}: sample reviews');
        expect(await apps.upgradeFromTemplate(id, t), isFalse, reason: '${t.id}: nothing more the second time');
      }
    } finally {
      await apps.stopAll();
      await db.raw.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
