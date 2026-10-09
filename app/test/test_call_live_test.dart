// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_apps/app_data.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_core/services/auth.dart';
import 'package:localailine/state/app_state.dart';

/// Calls → Tests → "Run a test call", end to end with a real local model.
/// LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/test_call_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final support = Directory.systemTemp.createTempSync('tc_support').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => support);
  test('a test call books a table and is kept in Calls', () async {
    final dir = Directory.systemTemp.createTempSync('tc');
    final s = AppState(dbPath: '${dir.path}/s.db');
    await s.init();
    await s.startHost(port: 0);
    await s.completeSetup(await s.auth.createUser(name: 'Sam', username: 'owner', password: 'password-123', role: Role.owner));
    await s.setLlmModel(model!);
    await s.refreshEngine();
    final id = await s.apps.createFromTemplate(appTemplates.first);
    final turns = await s.testCall(
      goal: 'Book a table for 2 tomorrow at 7pm.',
      facts: ['Your name: Alex Morgan', 'Day: tomorrow', 'Time: 7pm', 'People: 2'],
      onLine: (who, text, time) => print('$who [${time['at'] ?? ''}${time['ms'] == null ? '' : ' · ${time['ms']} ms, first words ${time['first_ms']} ms'}]: $text'),
    );
    expect(turns.length, greaterThan(2));
    final calls = await s.db.all('calls', where: "direction = 'test'");
    print('CALL: ${calls.single['name']} | ${calls.single['summary']}');
    final rows = await AppData(s.db, id, (await s.apps.app(id))!.spec).list('reservations', manager: true);
    print('BOOKED: $rows');
    expect(rows, isNotEmpty);
    await s.apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 10)));
}
