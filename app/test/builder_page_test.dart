import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_builder.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/ollama.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/pages/builder_page.dart';
import 'package:provider/provider.dart';

import 'apps_test.dart' show restaurant;

/// Draws the "Build an app" page in each of its states. With LOCALAILINE_SHOTS=dir,
/// saves a picture of each.
void main() {
  final shots = Platform.environment['LOCALAILINE_SHOTS'];

  Future<void> fonts() async {
    for (final (family, file) in [('Plex', 'IBMPlexSans.ttf'), ('Bricolage', 'BricolageGrotesque.ttf'), ('PlexMono', 'IBMPlexMono-Regular.ttf')]) {
      final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync())));
      await l.load();
    }
    final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }

  testWidgets('builder page: list, wizard, build, detail', (t) async {
    await t.runAsync(fonts);
    t.view.physicalSize = const Size(1200, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    late AppState s;
    late int appId;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('builder_ui');
      s = AppState(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
      s.mcp = McpManager(s.db, openBrowser: (_) async {});
      s.apps = AppsManager(s.db, s.mcp, ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {})..addListener(s.refresh);
      s
        ..ollamaVersion = '1'
        ..llmModel = 'qwen3:4b-instruct'
        ..installedModels = [OllamaModel('qwen3:4b-instruct', 1, '4B', 'Q4')];
      // A ready-made app: its pages have banners (no table) — this once crashed the app page.
      final spec = AppSpec.fromJson(appTemplates.first.spec.cast<String, dynamic>());
      final now = DateTime.now().millisecondsSinceEpoch;
      appId = await s.db.insert('apps', {
        'name': spec.name, 'request': 'I have a restaurant…', 'spec': jsonEncode(spec.toJson()), 'port': 8790, 'pin': '123456', 'created_at': now, 'updated_at': now,
      });
    });

    final key = GlobalKey();
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
        await t.pump();
      }
      expect(t.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await settle();
      if (shots == null) return;
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await t.pumpWidget(ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(color: const Color(0xFFF4F6F9), padding: const EdgeInsets.all(28), child: const SingleChildScrollView(child: BuilderPage())),
          ),
        ),
      ),
    ));
    await shot('1-list');
    expect(find.text('Trattoria Bella'), findsNWidgets(2)); // your app + the template card
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Use this'), findsNWidgets(appTemplates.length));
    expect(find.text('Describe your own'), findsOneWidget);

    // Wizard: describe.
    s.apps.newJob();
    await shot('2-describe');
    expect(find.text('What do you want?'), findsOneWidget);

    // Wizard: questions + style.
    s.apps.job!
      ..request = 'I have a restaurant'
      ..questions = ['Do customers order at the table?']
      ..stage = 'questions';
    s.apps.editPlan(s.apps.job!, AppSpec.fromJson(restaurant));
    await shot('2b-questions');
    expect(find.text('Elegant'), findsOneWidget);

    // Wizard: plan.
    final j = s.apps.job!
      ..request = 'restaurant'
      ..plan = AppSpec.fromJson(restaurant)
      ..stage = 'plan';
    j.pictures.add((base64Encode(File('assets/fonts/IBMPlexSans.ttf').readAsBytesSync().sublist(0, 10)), PictureNotes(kind: 'website', style: 'clean, airy', accent: '#C0392B')));
    s.apps.editPlan(j, j.plan!);
    await shot('3-plan');
    expect(find.text('Data it keeps'), findsOneWidget);
    expect(find.text('Build it'), findsOneWidget);

    // Wizard: building.
    j.stage = 'build';
    j.steps.addAll([
      BuildStep('Design “Menu items”', () async => null)..state = BuildState.done..note = '3 fields: Name, Price, Category',
      BuildStep('Design “Orders”', () async => null)..state = BuildState.simple..note = 'The AI struggled here, so it got a simple version.',
      BuildStep('Design page “Order”', () async => null)..state = BuildState.working,
      BuildStep('Add example menu items', () async => null),
    ]);
    s.apps.editPlan(j, j.plan!);
    await shot('4-build');
    expect(find.text('Building, one piece at a time'), findsOneWidget);

    // One app's page.
    s.apps.cancelJob();
    await settle();
    await t.tap(find.text('Open'));
    await shot('5-detail');
    expect(find.text('Ava can use this app'), findsOneWidget);
    expect(find.text('Change it by describing'), findsOneWidget);
    expect(find.text('WEBSITE STYLE'), findsOneWidget);
    expect(appId, greaterThan(0));
  });
}
