import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/pages/live_calls.dart';
import 'package:provider/provider.dart';

/// Calls → live calls: each conversation word by word as it is said, then kept with the recent ones.
/// SHOTS=/tmp/shots flutter test test/live_calls_view_test.dart  (also saves pictures)
void main() {
  final shots = Platform.environment['SHOTS'];
  testWidgets('live calls stream both sides, then move to recent', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 1100));
    t.view.physicalSize = const Size(1000, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late AppState s;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('live_ui');
      s = AppState(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
    });
    final key = GlobalKey();
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 150)); // the live view redraws a few times a second
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
        home: Scaffold(body: RepaintBoundary(key: key, child: Container(color: const Color(0xFFF4F6F9), padding: const EdgeInsets.all(28), child: const SingleChildScrollView(child: LiveCallsPanel(always: true))))),
      ),
    ));
    const room = 'pstn-in-0-_+447700900123_x';
    s.liveText[room] = [LiveLine('ai', 'Hi, thanks for calling Kings Cut Barbers, this is Danny.', name: 'Danny', done: true)];
    // The caller speaking: words arrive, and change as hearing settles.
    s.liveCaller(room, 'Can I speak');
    await settle();
    expect(find.textContaining('Can I speak'), findsOneWidget);
    expect(find.textContaining('hearing…'), findsOneWidget);
    s.liveCaller(room, 'Can I speak to me a');
    s.liveCallerTurn(room, 'Can I speak to Mia, please?'); // what the AI got
    // The AI answering, a few words at a time, then the hand-over.
    s.liveAi(room, 'Of course, ');
    s.liveAi(room, 'one moment while I pass you to Mia.');
    await shot('live-1-streaming');
    expect(find.textContaining('Can I speak to Mia, please?'), findsOneWidget);
    expect(find.textContaining('one moment while I pass you to Mia. ▍'), findsOneWidget);
    expect(find.textContaining('speaking…'), findsOneWidget);
    s.liveAi(room, ' [voice:af_bella|Mia] Hi, it\'s Mia — you\'d like to book with me?');
    s.liveAiDone(room);
    await settle();
    expect(find.textContaining('passed to Mia'), findsOneWidget);
    expect(find.textContaining('Mia ·'), findsOneWidget);
    expect(find.textContaining('[voice'), findsNothing);
    await shot('live-2-handover');
    // The call ends: it moves to the recent conversations.
    s.liveCalls.remove(room);
    s.liveEnded(room);
    await settle();
    expect(find.text('No calls right now'), findsOneWidget);
    expect(find.text('Recent conversations'), findsOneWidget);
    await t.tap(find.textContaining('Can I speak to Mia, please?'));
    await shot('live-3-recent');
    expect(find.textContaining('passed to Mia'), findsOneWidget);
  });

  test('what the caller said shows once, even if the AI started and was cut off', () async {
    final tmp = Directory.systemTemp.createTempSync('live_once');
    final s = AppState(dbPath: '${tmp.path}/t.db');
    s.db = await Db.open(path: '${tmp.path}/t.db');
    const room = 'pstn-in-0-_+447700900656_vt8950-1';
    const said = "I'd like to book a table for two at 7:30 pm tonight, please. One of us is vegetarian.";
    s.liveCaller(room, said, done: true); // heard
    s.liveAiSpoken(room, 'One'); // the start of an answer, cut off as they went on
    s.liveCallerTurn(room, said); // what the AI was given
    s.liveAiSpoken(room, "I'm sorry, there's no table at 7:30 pm.", done: true);
    final lines = s.liveText[room]!;
    expect(lines.where((l) => l.who == 'caller').length, 1);
    expect(lines.map((l) => l.text), isNot(contains('One')));
    expect(lines.last.text, contains('no table'));
  });
}
