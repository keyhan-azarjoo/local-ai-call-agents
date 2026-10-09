import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine_core/data/db.dart';
import 'package:localailine_apps/app_data.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_apps/apps_manager.dart';
import 'package:localailine_core/services/mcp/mcp_manager.dart';

/// Pictures of the business apps for the README: their public websites and the manager pages.
/// The apps are made from the ready-made templates in a temporary database (with the templates'
/// photos), filled with made-up bookings and orders over the last two weeks, served on free ports,
/// and photographed with headless Chrome (tool/capture_pages.mjs). Nothing else is touched.
///
///   SHOTS=../docs/screenshots flutter test test/screenshots_sites_test.dart
/// (or tool/screenshots.sh). Needs Google Chrome, Node 22+ and internet (for the template photos).
void main() {
  final shots = Platform.environment['SHOTS'];

  test('README pictures of the websites and manager pages', () async {
    final tmp = Directory.systemTemp.createTempSync('ll_sites');
    final db = await Db.open(path: '${tmp.path}/localailine.db');
    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    try {
      final made = <String, BuiltApp>{};
      for (final id in ['restaurant', 'barber', 'hotel', 'shop', 'garage']) {
        final appId = await apps.createFromTemplate(appTemplates.firstWhere((t) => t.id == id), ava: false);
        made[id] = (await apps.app(appId))!;
      }
      final demo = _Demo(db);
      await demo.restaurant(made['restaurant']!);
      await demo.barber(made['barber']!);
      await demo.garage(made['garage']!);
      await demo.shop(made['shop']!);
      await demo.hotel(made['hotel']!);

      String site(String app, [String path = '/']) => 'http://127.0.0.1:${made[app]!.port}$path';
      String manage(String app, String view) => 'http://127.0.0.1:${made[app]!.port}/manage#pin=${made[app]!.pin}&v=${Uri.encodeComponent(view)}';
      final plan = <Map<String, Object>>[
        {'name': 'site-restaurant-home', 'url': site('restaurant')},
        {'name': 'site-restaurant-menu', 'url': site('restaurant', '/p/menu'), 'scrollTo': '.menu-sec', 'offset': -56},
        {'name': 'site-restaurant-booking', 'url': site('restaurant', '/p/book'), 'scrollTo': '.avail', 'offset': -56, 'clickText': '19:30'},
        {'name': 'site-barber-home', 'url': site('barber')},
        {'name': 'site-hotel-rooms', 'url': site('hotel', '/p/book'), 'action': 'stay', 'offset': -56},
        {'name': 'site-shop-catalogue', 'url': site('shop', '/p/products'), 'scrollTo': 'section.sec', 'offset': -56},
        {'name': 'site-mobile', 'url': site('restaurant'), 'width': 390, 'height': 844, 'scale': 2, 'mobile': true},
        {'name': 'manage-dashboard', 'url': manage('restaurant', 'overview')},
        {'name': 'manage-table', 'url': manage('restaurant', 't:reservations')},
        {'name': 'manage-board', 'url': manage('restaurant', 't:orders'), 'action': 'board', 'width': 1940, 'height': 900},
        {'name': 'manage-calendar', 'url': manage('garage', 't:bookings'), 'action': 'calendar'},
        {'name': 'manage-customers', 'url': manage('restaurant', 'customers')},
      ];
      // The websites as on an evening when the restaurant and the barber are open.
      for (final shot in plan.where((s) => '${s['name']}'.startsWith('site-'))) {
        shot['clock'] = '18:30';
      }
      final planFile = File('${tmp.path}/plan.json')..writeAsStringSync(jsonEncode({'out': Directory(shots!).absolute.path, 'shots': plan}));
      Directory(shots).createSync(recursive: true);
      final r = await Process.run('node', ['tool/capture_pages.mjs', planFile.path]);
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      expect(r.exitCode, 0, reason: 'capture_pages.mjs failed');
    } finally {
      await apps.stopAll();
      await db.raw.close();
    }
  }, skip: shots == null ? 'set SHOTS=<folder> to make the pictures' : null, timeout: const Timeout(Duration(minutes: 10)));
}

/// Made-up customers and what they booked or ordered. Names are fictional; numbers are from the
/// UK's range for drama (07700 900xxx).
class _Demo {
  _Demo(this.db);
  final Db db;
  final rnd = Random(7);
  final now = DateTime.now();

  static const people = [
    'Sophie Turner', 'Daniel Price', 'Grace Okafor', 'Tom Hughes', 'Amelia Clarke', 'Oliver Bennett', 'Priya Shah', 'Lucas Martin',
    'Hannah Lewis', 'Jacob Evans', 'Chloe Robinson', 'Ethan Wright', 'Isla Campbell', 'Noah Patel', 'Ruby Walker', 'Samuel Green',
    'Mia Hall', 'Leo Thompson', 'Freya Edwards', 'Arjun Mehta', 'Zara Ahmed', 'Callum Reid', 'Ellie Ward', 'Max Fischer',
  ];

  /// Someone's number (the same person always has the same one, so regulars show up as regulars).
  String phone(int i) => '07700 900${(101 + (i % people.length) * 37).toString().padLeft(3, '0')}';

  /// A customer: often a regular (the first few people), sometimes someone new.
  int who() => rnd.nextInt(5) == 0 ? rnd.nextInt(8) : rnd.nextInt(people.length);
  Map<String, String> person() {
    final i = who();
    return {'name': people[i], 'phone': phone(i)};
  }
  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);

  Future<AppData> data(BuiltApp a) async => AppData(db, a.id, a.spec);

  /// Saves a record as if it came in at [at] (the dashboard counts records by when they came in).
  Future<void> add(AppData d, String table, Map<String, dynamic> values, DateTime at) async {
    try {
      final id = await d.add(table, values, manager: true, via: 'seed');
      final ms = at.isAfter(now) ? now.millisecondsSinceEpoch : at.millisecondsSinceEpoch;
      await db.raw.update('app_rows', {'created_at': ms, 'updated_at': ms}, where: 'id = ?', whereArgs: [id]);
    } on AppDataError catch (e) {
      stderr.writeln('(skipped a demo $table record: $e)');
    }
  }

  /// When a booking for [d] at [time] was made: a few days before, never in the future.
  DateTime madeFor(DateTime d, {int maxDaysBefore = 6}) {
    final t = d.subtract(Duration(days: rnd.nextInt(maxDaysBefore + 1), hours: rnd.nextInt(10)));
    final cap = now.subtract(Duration(minutes: 20 + rnd.nextInt(300)));
    return t.isAfter(cap) ? cap : t;
  }

  /// Some time on day [offset] (today: before now).
  DateTime cameIn(int offset) {
    final d = day(offset).add(Duration(hours: 11 + rnd.nextInt(10), minutes: rnd.nextInt(60)));
    return d.isAfter(now) ? now.subtract(Duration(minutes: 5 + rnd.nextInt(240))) : d;
  }

  String time(int fromHour, int toHour) => '${(fromHour + rnd.nextInt(toHour - fromHour)).toString().padLeft(2, '0')}:${rnd.nextBool() ? '00' : '30'}';

  Future<void> restaurant(BuiltApp a) async {
    final d = await data(a);
    const occasions = ['Birthday', 'Anniversary', 'Business', 'Date night', 'Other'];
    var p = 0;
    // Table bookings: the last two weeks, today and the week ahead.
    for (var off = -13; off <= 7; off++) {
      final n = off == 0 ? 9 : 2 + rnd.nextInt(off.isNegative ? 4 : 3);
      for (var i = 0; i < n; i++, p++) {
        final at = off == 0 ? ['12:30', '13:00', '13:30', '18:00', '18:30', '19:00', '19:30', '20:00', '20:30'][i] : time(12, 21);
        // Today: finished, seated or still to come, by the time it is now.
        final mins = int.parse(at.substring(0, 2)) * 60 + int.parse(at.substring(3)) - (now.hour * 60 + now.minute);
        final status = off < 0
            ? (rnd.nextInt(16) == 0 ? 'No-show' : rnd.nextInt(10) == 0 ? 'Cancelled' : 'Finished')
            : off == 0
                ? (mins < -100 ? 'Finished' : mins < 0 ? 'Seated' : 'Confirmed')
                : 'Confirmed';
        await add(d, 'reservations', {
          ...person(), 'date': ymd(day(off)), 'time': at,
          'guests': 2 + rnd.nextInt(5), 'status': status, if (rnd.nextInt(4) == 0) 'occasion': occasions[rnd.nextInt(occasions.length)],
          if (rnd.nextInt(6) == 0) 'requests': ['Window table if possible', 'High chair please', 'One guest is vegan', 'Quiet corner, please'][rnd.nextInt(4)],
        }, madeFor(day(off)));
      }
    }
    // Food orders: collection, delivery and to tables.
    const dishes = ['Margherita', 'Diavola', 'Tartufo', 'Cacio e pepe', 'Linguine allo scoglio', 'Tiramisù', 'Garlic focaccia', 'Burrata & heritage tomatoes', 'Aperol spritz', 'Rocket & parmesan salad'];
    const streets = ['4 Quay Road', '17 Harbour Street', '9 Chapel Row', '22 Mill Lane', '3 Station Approach'];
    for (var off = -13; off <= 0; off++) {
      final n = off == 0 ? 7 : 2 + rnd.nextInt(5);
      for (var i = 0; i < n; i++, p++) {
        final type = ['Collection', 'Delivery', 'Dine-in'][rnd.nextInt(3)];
        final items = <String>{for (var k = 0; k < 1 + rnd.nextInt(3); k++) dishes[rnd.nextInt(dishes.length)]};
        await add(d, 'orders', {
          ...person(), 'type': type,
          if (type == 'Delivery') ...{'address': streets[rnd.nextInt(streets.length)], 'postcode': 'HB1 ${1 + rnd.nextInt(8)}CD'},
          if (type == 'Dine-in') 'table': '${1 + rnd.nextInt(7)}',
          'items': [for (final it in items) {'name': it, 'qty': 1 + rnd.nextInt(2)}],
          'ready_at': time(12, 21),
          'status': off < 0 ? (rnd.nextInt(15) == 0 ? 'Cancelled' : 'Done') : ['New', 'New', 'Preparing', 'Preparing', 'Ready', 'Out for delivery', 'Done'][i % 7],
          'payment': off < 0 || i > 3 ? (rnd.nextBool() ? 'Paid card' : 'Paid cash') : 'Unpaid',
          if (rnd.nextInt(5) == 0) 'notes': ['No onions please', 'Nut allergy', 'Extra chilli', 'Ring the bell twice'][rnd.nextInt(4)],
        }, cameIn(off));
      }
    }
    await add(d, 'private_events', {'name': 'Tom Hughes', 'phone': phone(3), 'date': ymd(day(37)), 'guests': 18, 'event_type': 'Corporate', 'notes': 'Team dinner, set menu, one vegetarian.', 'status': 'Enquiry'}, cameIn(-1));
    await add(d, 'vouchers', {'name': 'Amelia Clarke', 'phone': phone(4), 'amount': 50, 'recipient': 'Mum', 'message': 'Happy birthday! Enjoy the pizza.', 'status': 'Requested'}, cameIn(0));
  }

  Future<void> barber(BuiltApp a) async {
    final d = await data(a);
    const services = ['Skin fade', 'Classic cut', 'Beard trim', 'Cut & beard', 'Hot towel shave', 'Kids cut'];
    const barbers = ['Tony', 'Jay', 'Ali'];
    var p = 5;
    for (var off = -13; off <= 5; off++) {
      final n = off == 0 ? 8 : 3 + rnd.nextInt(5);
      for (var i = 0; i < n; i++, p++) {
        await add(d, 'appointments', {
          ...person(), 'service': services[rnd.nextInt(services.length)], 'barber': barbers[i % 3],
          'date': ymd(day(off)), 'time': time(9, 18), 'status': off < 0 ? (rnd.nextInt(10) == 0 ? 'No-show' : 'Done') : 'Booked',
        }, madeFor(day(off)));
      }
    }
  }

  Future<void> garage(BuiltApp a) async {
    final d = await data(a);
    const cars = [('Ford Focus', 'LK16 RTX'), ('VW Golf', 'MA19 PLE'), ('Toyota Yaris', 'YR21 KDF'), ('Nissan Qashqai', 'BD17 WNS'), ('BMW 3 Series', 'GX68 HJU'), ('Kia Sportage', 'NV20 ZPT'), ('Vauxhall Corsa', 'PO15 LMC'), ('Tesla Model 3', 'EV22 TSL')];
    const services = ['MOT', 'Full service', 'Brake pads & discs', 'Diagnostics', 'Tyres', 'Air conditioning re-gas'];
    final rows = await d.list('services', manager: true);
    final names = [for (final r in rows) '${r['name']}'];
    var p = 9;
    for (var off = -20; off <= 22; off++) {
      if (day(off).weekday == DateTime.sunday || rnd.nextInt(3) == 0) continue;
      final n = 1 + rnd.nextInt(2);
      for (var i = 0; i < n; i++, p++) {
        final (car, plate) = cars[p % cars.length];
        final want = names.where((x) => services.any((s) => x.toLowerCase().contains(s.split(' ').first.toLowerCase()))).toList();
        await add(d, 'bookings', {
          ...person(), 'car': car, 'plate': plate,
          'services': [want.isEmpty ? names[p % names.length] : want[p % want.length]],
          'date': ymd(day(off)), 'mileage': 18000 + rnd.nextInt(90000),
          'status': off < 0 ? 'Collected' : off == 0 ? ['In the workshop', 'Ready'][i % 2] : 'Booked',
          if (rnd.nextInt(4) == 0) 'notes': ['Squeal when braking', 'Engine light on', 'Pulls to the left', 'Due its MOT'][rnd.nextInt(4)],
        }, madeFor(day(off), maxDaysBefore: 10));
      }
    }
  }

  Future<void> shop(BuiltApp a) async {
    final d = await data(a);
    // Photos for the products the template has none for, so no card in the catalogue is blank.
    const photos = {
      'Free-range eggs (6)': '1506976785307-8732e854ad03',
      'Extra-virgin olive oil': '1474979266404-7eaacbcd87c5',
      'Sparkling lemonade': '1621263764928-df1444c5e859',
      'Eco washing-up liquid': '1563453392212-326f5e854473',
      'Wildflower honey': '1587049352851-8d4e89133924',
      'Dark chocolate (70%)': '1511381939415-e44015466834',
    };
    final files = Directory('${File(db.path).parent.path}/apps/${a.id}/files')..createSync(recursive: true);
    for (final r in await d.list('products', manager: true)) {
      final id = photos['${r['name']}'];
      if (id == null || '${r['photo'] ?? ''}'.isNotEmpty) continue;
      final res = await http.get(Uri.parse('https://images.unsplash.com/photo-$id?w=900&q=78&fm=jpg&fit=crop'));
      if (res.statusCode != 200) continue;
      final name = '${id.replaceAll('-', '')}.jpg';
      File('${files.path}/$name').writeAsBytesSync(res.bodyBytes);
      await d.update('products', r['id'] as int, {'photo': '/files/$name'});
    }
    final products = [for (final r in await d.list('products', manager: true)) '${r['name']}'];
    var p = 2;
    for (var off = -10; off <= 0; off++) {
      for (var i = 0; i < 1 + rnd.nextInt(3); i++, p++) {
        final pick = day(off).add(Duration(hours: 10 + rnd.nextInt(8)));
        await add(d, 'orders', {
          ...person(), 'type': 'Collection',
          'items': [{'name': products[rnd.nextInt(products.length)], 'qty': 1 + rnd.nextInt(3)}],
          'pickup': '${ymd(pick)} ${pick.hour.toString().padLeft(2, '0')}:00', 'status': off < 0 ? 'Collected' : 'Packing',
        }, cameIn(off));
      }
    }
  }

  Future<void> hotel(BuiltApp a) async {
    final d = await data(a);
    final rooms = [for (final r in await d.list('rooms', manager: true)) '${r['name']}'];
    var p = 11;
    for (var i = 0; i < 6; i++, p++) {
      final inDay = day(-3 + i * 3);
      await add(d, 'bookings', {
        ...person(), if (rooms.isNotEmpty) 'room': rooms[i % rooms.length],
        'check_in': ymd(inDay), 'check_out': ymd(inDay.add(Duration(days: 2 + i % 3))), 'guests': 2, 'status': i < 2 ? 'Checked in' : 'Confirmed',
      }, madeFor(inDay, maxDaysBefore: 12));
    }
  }
}
