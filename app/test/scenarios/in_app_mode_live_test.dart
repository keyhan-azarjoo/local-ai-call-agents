// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_apps/app_data.dart';
import 'package:localailine_apps/app_spec.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_core/services/auth.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_engine/scenario_runner.dart';

/// "Run test scenarios" in the app: on your own apps (an older restaurant app is brought up to
/// date, a barber shop is made), your own assistant, results checked on the websites.
/// LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/scenarios/in_app_mode_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final support = Directory.systemTemp.createTempSync('ia_support').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => support);
  test('scenarios in your own apps', () async {
    final dir = Directory.systemTemp.createTempSync('ia');
    final s = AppState(dbPath: '${dir.path}/s.db');
    await s.init();
    await s.startHost(port: 0);
    await s.completeSetup(await s.auth.createUser(name: 'Alex', username: 'owner', password: 'password-123', role: Role.owner));
    await s.setLlmModel(model!);
    await s.refreshEngine();
    // Like Pasargad: made from the older restaurant template (orders to a table only).
    final old = appTemplates.first.spec.cast<String, dynamic>();
    final oldTables = [
      for (final t in (old['tables'] as List).cast<Map>())
        t['id'] == 'orders'
            ? {...t, 'fields': [for (final f in (t['fields'] as List).cast<Map>()) if (!const {'phone', 'type', 'address', 'postcode', 'ready_at'}.contains(f['id'])) f['id'] == 'table' ? {...f, 'when': null} : f]}
            : t,
    ];
    final id = await s.apps.createFromTemplate(appTemplates.first, name: 'Pasargad');
    await s.apps.saveSpec(id, AppSpec.fromJson({...(await s.apps.app(id))!.spec.toJson(), 'tables': oldTables}));
    print('before: orders fields ${(await s.apps.app(id))!.spec.table('orders')!.fields.map((f) => f.id).toList()}');

    final all = [for (final f in ['scenarios.json', 'journeys.json']) ...(jsonDecode(File('assets/scenarios/$f').readAsStringSync()) as List).cast<Map<String, dynamic>>()];
    final pick = [
      all.firstWhere((x) => x['intent'] == 'order_delivery'),
      all.firstWhere((x) => x['app'] == 'shop' && x['intent'] == 'order_delivery'),
      all.firstWhere((x) => x['app'] == 'barber' && x['intent'] == 'book'),
      all.firstWhere((x) => x['intent'] == 'journey_team'),
    ];
    final r = ScenarioRunner(s);
    for (final sc in pick) {
      final res = await r.run(sc);
      print('${sc['id']}: ${res['pass']} ${res['failures']}');
      for (final c in (res['calls'] as List).cast<Map>()) {
        for (final t in (c['turns'] as List? ?? [])) {
          print('   $t');
        }
      }
    }
    await r.close();
    final apps = await s.apps.apps();
    print('apps now: ${apps.map((a) => '${a.name}:${a.port}').toList()}');
    print('after: orders fields ${(await s.apps.app(id))!.spec.table('orders')!.fields.map((f) => f.id).toList()}');
    final barber = apps.firstWhere((a) => a.name.contains('Kings Cut'));
    print('barber bookings: ${await AppData(s.db, barber.id, barber.spec).list('appointments', manager: true)}');
    print('agents: ${(await s.db.all('agents')).map((a) => '${a['name']} (${a['role']})').toList()}  focus=${s.focusApp}');
    print('skills: ${(await s.db.all('skills')).map((a) => a['name']).toList()}');
    final shop = apps.firstWhere((a) => a.name.contains('Corner'));
    print('shop orders: ${await AppData(s.db, shop.id, shop.spec).list('orders', manager: true)}');
    expect(apps.any((a) => a.name.contains('Kings Cut')), true);
    expect((await s.apps.app(id))!.spec.table('orders')!.fields.any((f) => f.id == 'type'), true);
    await s.apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 30)));
}
