import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/state/scenario_runner.dart';

/// Test runs in the app reuse the businesses they made before, even after the templates gained
/// tables (they used to make a second copy of each, and the AI then saw two barbers, two clinics…),
/// and never take a look-alike business (a barber's and a salon's tables are nearly the same).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('reuse');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);

  test('reuses its own business, upgraded, and never a look-alike', () async {
    final s = AppState(dbPath: '${tmp.path}/t.db');
    await s.init();
    addTearDown(() => s.apps.stopAll());
    AppTemplate tpl(String id) => appTemplates.firstWhere((t) => t.id == id);

    // A barber made from an older template (without its newer tables).
    final barber = await s.apps.createFromTemplate(tpl('barber'));
    final spec = (await s.apps.app(barber))!.spec.toJson();
    final tables = (spec['tables'] as List).cast<Map>();
    final newer = [for (final t in tables.skip(4)) '${t['id']}'];
    expect(newer, isNotEmpty, reason: 'the barber template should have newer tables to drop');
    final older = tables.take(4).toList();
    await s.apps.saveSpec(barber, AppSpec.fromJson({...spec, 'tables': older}));

    final r = ScenarioRunner(s);
    await r.prepareApps(['barber', 'salon']);
    expect(r.appIds['barber'], barber, reason: 'the existing barber is reused');
    expect(r.appIds['salon'], isNot(barber), reason: 'the salon is not the barber');
    expect((await s.apps.apps()).length, 2);
    expect((await s.apps.app(barber))!.spec.tables.map((t) => t.id), containsAll(newer), reason: 'brought up to date');

    // The next run (after a restart): the same two, no copies.
    final again = ScenarioRunner(s);
    await again.prepareApps(['barber', 'salon']);
    expect(again.appIds, r.appIds);
    expect((await s.apps.apps()).length, 2);
    await r.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
