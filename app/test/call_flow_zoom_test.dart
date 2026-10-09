import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/agent_templates.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/app_model.dart';
import 'package:localailine_ui/theme/tokens.dart';
import 'package:localailine_ui/ui/pages/call_flow_page.dart';
import 'package:provider/provider.dart';

/// The call flow: zoom in and out, fit everything, tidy the cards, go to an agent.
/// SHOTS=/tmp/shots flutter test test/call_flow_zoom_test.dart  (also saves pictures)
void main() {
  final shots = Platform.environment['SHOTS'];
  testWidgets('zoom, fit, tidy and find on the call flow', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 1000));
    t.view.physicalSize = const Size(1300, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late AppState s;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('flow_ui');
      s = AppState(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
      await s.setUpTeam(businessTemplates.first);
    });
    final key = GlobalKey();
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 100));
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

    await t.pumpWidget(ListenableProvider<AppModel>.value(
      value: s,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: RepaintBoundary(key: key, child: const SingleChildScrollView(padding: EdgeInsets.all(24), child: CallFlowPage()))),
      ),
    ));
    await shot('flow-1-fit');
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    String pct() => (t.widget(find.textContaining(RegExp(r'^\d+%$'))) as Text).data!;
    final before = int.parse(pct().replaceAll('%', ''));
    await t.tap(find.byTooltip('Zoom in'));
    await settle();
    expect(int.parse(pct().replaceAll('%', '')), greaterThan(before));
    await t.tap(find.byTooltip('Zoom out'));
    await t.tap(find.byTooltip('Zoom out'));
    await settle();
    expect(int.parse(pct().replaceAll('%', '')), lessThan(before));
    await t.tap(find.byTooltip('Tidy up: set the cards out neatly'));
    await shot('flow-2-tidy');
    await t.tap(find.byTooltip('Go to an agent'));
    await settle();
    await t.tap(find.text(businessTemplates.first.roles.last.name).last);
    await shot('flow-3-found');
    await t.tap(find.byTooltip('Taller canvas'));
    await settle();
    expect(find.byTooltip('Smaller canvas'), findsOneWidget);
  });
}
