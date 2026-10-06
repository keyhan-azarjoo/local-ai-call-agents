import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/pages/test_runs_section.dart';
import 'package:provider/provider.dart';

/// The Calls → Tests view: phone-call scenario results as conversations.
/// SHOTS=/tmp/shots flutter test test/test_runs_view_test.dart  (also saves pictures)
void main() {
  final shots = Platform.environment['SHOTS'];
  testWidgets('test calls: summary, list, one conversation', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 1400));
    t.view.physicalSize = const Size(1100, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late AppState s;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('runs_ui');
      s = AppState(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
      Directory('${tmp.path}/test-runs').createSync();
      final src = File('test/scenarios/out/results.jsonl');
      File('${tmp.path}/test-runs/results.jsonl').writeAsStringSync(src.existsSync()
          ? src.readAsLinesSync().take(40).join('\n')
          : '{"id":"restaurant-0001","app":"restaurant","intent":"book_table","setup":"solo","style":"terse","pass":false,"seconds":40,"failures":["date: expected \\"2026-10-10\\", website has \\"2026-10-08\\""],"calls":[{"from":"A","seconds":40,"turns":["AI: Hi, thanks for calling Trattoria Bella.","CALLER: A table for two on Saturday at 7pm.","AI: Booked!"],"tools":["add_reservations({}) → Done."],"passed_to":[]}]}');
    });
    final key = GlobalKey();
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
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
        home: Scaffold(body: RepaintBoundary(key: key, child: Container(color: const Color(0xFFF4F6F9), padding: const EdgeInsets.all(28), child: const SingleChildScrollView(child: TestRunsSection())))),
      ),
    ));
    await shot('runs-1-list');
    expect(find.textContaining('test scenarios passed'), findsOneWidget);
    await t.tap(find.byType(InkWell).at(4));
    await t.tap(find.textContaining('restaurant ·').first);
    await shot('runs-2-conversation');
    expect(find.text('Caller'), findsWidgets);
    await t.tap(find.text('Close'));
    await settle();
  });
}
