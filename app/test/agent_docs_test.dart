import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/state/app_state.dart';

/// A business's own agent uses that business's knowledge only: on a voice test call, the Trattoria
/// Bella receptionist read out another restaurant's opening hours from a document shared with all.
void main() {
  test('business agents get only the documents they were given', () async {
    final tmp = Directory.systemTemp.createTempSync('docs');
    final s = AppState(dbPath: '${tmp.path}/t.db');
    s.db = await Db.open(path: '${tmp.path}/t.db');
    final rec = await s.accessOf({'role': 'Receptionist · Trattoria Bella', 'access': '{"skills":[1],"passTo":[2]}'});
    expect(rec?.docs, isEmpty, reason: 'no shared documents unless given');
    expect(rec?.skills, {1});
    final given = await s.accessOf({'role': 'Receptionist · Trattoria Bella', 'access': '{"docs":[7]}'});
    expect(given?.docs, {7});
    final none = await s.accessOf({'role': 'Bookings · Kings Cut Barbers', 'access': null});
    expect(none?.docs, isEmpty);
    // The main assistant (no business of its own) keeps every shared document.
    expect((await s.accessOf({'role': 'Receptionist', 'access': '{"skills":[1]}'}))?.docs, isNull);
    await s.db.raw.close();
  });
}
