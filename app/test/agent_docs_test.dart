import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/ollama.dart';
import 'package:localailine/state/app_state.dart';

/// A business's own agent uses that business's knowledge only: on a voice test call, the Trattoria
/// Bella receptionist read out another restaurant's opening hours from a document shared with all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test("the owner's chat doesn't take on a business's call skills", () async {
    final tmp = Directory.systemTemp.createTempSync('skills');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
    final s = AppState(dbPath: '${tmp.path}/t.db');
    await s.init();
    await s.db.insert('apps', {'name': 'Kings Cut Barbers', 'request': 'r', 'pin': '1', 'spec': '{"name":"Kings Cut Barbers","tables":[],"pages":[]}', 'port': 0, 'status': 'stopped', 'created_at': 0, 'updated_at': 0});
    await s.db.insert('skills', {'name': 'Kings Cut Barbers: services', 'description': 'd', 'instructions': 'Say: thanks for calling Kings Cut', 'enabled': 1});
    await s.db.insert('skills', {'name': 'Take a message', 'description': 'd', 'instructions': 'Take a short message', 'enabled': 1});
    String system(List<ChatMessage> m) => m.firstWhere((x) => x.role == 'system').content;
    final chat = await s.prepare([ChatMessage('system', 'You are Ava.'), ChatMessage('user', 'hi')], scopes: {'me', 'contacts', 'all'});
    expect(system(chat), isNot(contains('Kings Cut')));
    expect(system(chat), contains('Take a short message'));
    // On a call answered by the barber's receptionist, its skills are in.
    final call = await s.prepare([ChatMessage('system', 'You are Danny.'), ChatMessage('user', 'hi')], scopes: {'all'}, access: const AgentAccess(skills: {1}));
    expect(system(call), contains('thanks for calling Kings Cut'));
  });
}
