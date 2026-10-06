import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/abilities.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('orders, bookings and messages are saved plainly', () async {
    final dir = await Directory.systemTemp.createTemp('ll_ab');
    addTearDown(() => dir.delete(recursive: true));
    final db = await Db.open(path: '${dir.path}/a.db');
    await Abilities.run(db, 'place_order', {
      'name': 'John',
      'items': [
        {'quantity': 1, 'name': 'Fish & chips', 'price': 16.0}
      ],
      'total': 16.0,
      'delivery': 'collection',
    }, agent: 'Sam');
    await Abilities.run(db, 'book', {'name': 'Ann', 'when': '2026-10-07 19:00', 'service': 'Table', 'people': 4}, agent: 'Lily');
    await Abilities.run(db, 'take_message', {'name': 'Bo', 'phone': '0770', 'message': 'Call me back', 'urgent': true});
    final rows = await db.all('requests', orderBy: 'id');
    expect(rows.map((r) => r['summary']), ['1 × Fish & chips (16.00) · 16.00 · collection', 'Table for 4 · 2026-10-07 19:00', 'URGENT: Call me back']);
    expect(rows.map((r) => r['kind']), ['order', 'booking', 'message']);
  });
}
