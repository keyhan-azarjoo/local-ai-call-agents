import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/app_model.dart';
import 'package:localailine_ui/state/call_monitor.dart';
import 'package:localailine_ui/theme/tokens.dart';
import 'package:localailine_ui/ui/pages/live_calls.dart';
import 'package:provider/provider.dart';

/// Calls → live calls: Listen, Take over (then Hand back to AI / End call), and on voice test
/// calls Speak as the caller / Hand back, each shown when it applies.
void main() {
  testWidgets('live call cards offer listen, take over and speak as the caller', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 1400));
    t.view.physicalSize = const Size(1100, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late AppState s;
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('live_ctl');
      s = AppState(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
    });
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(t.takeException(), isNull);
    }

    await t.pumpWidget(ListenableProvider<AppModel>.value(
      value: s,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(20), child: LiveCallsPanel(always: true))),
      ),
    ));
    const real = 'pstn-in-1-_+447700900123_a1';
    const vt = 'pstn-in-0-_+447700900999_vt1712345678';
    s.liveText[real] = [LiveLine('ai', 'Hi, thanks for calling Kings Cut Barbers.', name: 'Danny', done: true)];
    s.liveCaller(real, 'Can I book a haircut?', done: true);
    s.liveText[vt] = [LiveLine('ai', 'Hello, this is Ava.', done: true)];
    s.liveCaller(vt, 'Hi, I would like a table.', done: true);
    await settle();
    Finder inCard(String room, Finder f) => find.descendant(of: find.byWidgetPredicate((w) => w is CallControls && w.room == room), matching: f);

    // Nobody on the calls: listen or take over either; the voice test call can also be spoken on as its caller.
    expect(find.text('Listen'), findsNWidgets(2));
    expect(find.text('Take over'), findsNWidgets(2));
    expect(find.text('Speak as the caller'), findsOneWidget);
    expect(inCard(vt, find.text('Speak as the caller')), findsOneWidget);
    expect(inCard(real, find.text('Speak as the caller')), findsNothing);
    expect(find.text('Hand back to AI'), findsNothing);
    expect(find.text('End call'), findsNothing);

    // Without live voice running, nothing is joined (and nothing breaks).
    await t.tap(inCard(real, find.text('Listen')));
    await settle();
    expect(s.callMonitor.modeOf(real), MonitorMode.off);

    // Listening in on the real call: stop listening, or take over from there.
    s.callMonitor.debugSet(real, MonitorMode.listening, level: .5, speaking: 'caller');
    await settle();
    expect(inCard(real, find.text('Stop listening')), findsOneWidget);
    expect(inCard(real, find.text('Listen')), findsNothing);
    expect(inCard(real, find.text('Take over')), findsOneWidget);
    expect(inCard(real, find.text('Listening · the caller is speaking')), findsOneWidget);
    expect(inCard(real, find.bySemanticsLabel('Audio level')), findsOneWidget);
    expect(inCard(vt, find.text('Listen')), findsOneWidget); // the other call is untouched

    // Taken over: the owner is on the call; hand back to the AI, or hang up.
    await t.runAsync(() async => s.liveTakeover(real, 'Keyhan'));
    s.callMonitor.debugSet(real, MonitorMode.takenOver, speaking: 'owner');
    s.liveOnCall(real, owner: true, caller: false);
    await settle();
    expect(inCard(real, find.text('Hand back to AI')), findsOneWidget);
    expect(inCard(real, find.text('End call')), findsOneWidget);
    expect(inCard(real, find.text('Mute')), findsOneWidget);
    expect(inCard(real, find.text('Take over')), findsNothing);
    expect(inCard(real, find.text('Listen')), findsNothing);
    expect(inCard(real, find.text('You’re speaking')), findsOneWidget);
    expect(find.text('Keyhan is speaking'), findsOneWidget);
    expect(find.textContaining('Keyhan took over the call'), findsOneWidget);
    s.callMonitor.debugSet(real, MonitorMode.takenOver, muted: true);
    s.liveOnCall(real, owner: false, caller: false);
    await settle();
    expect(inCard(real, find.text('Unmute')), findsOneWidget);
    expect(find.text('Keyhan is on the call'), findsOneWidget);

    // The voice test call: the owner speaks as its caller, and their words are labelled with their name.
    s.liveCallerAs(vt, 'Keyhan');
    s.liveCaller(vt, 'Actually, make that four people.', done: true);
    await settle();
    expect(inCard(vt, find.text('Hand back')), findsOneWidget);
    expect(inCard(vt, find.text('Speak as the caller')), findsNothing);
    expect(find.textContaining('Keyhan (as caller) ·'), findsOneWidget);
    expect(find.textContaining('Keyhan is speaking as the caller'), findsOneWidget);
    s.liveCallerAs(vt, null);
    s.liveCaller(vt, 'Thanks, bye.', done: true);
    await settle();
    expect(inCard(vt, find.text('Speak as the caller')), findsOneWidget);
    expect(find.textContaining('The simulated caller is back'), findsOneWidget);
    expect(find.textContaining('Keyhan (as caller) ·'), findsOneWidget); // only the line they said

    // Handed back: the AI is on the call again.
    s.callMonitor.debugSet(real, MonitorMode.off);
    s.liveHandedBack(real);
    await settle();
    expect(inCard(real, find.text('Listen')), findsOneWidget);
    expect(find.textContaining('Handed back to the AI'), findsOneWidget);
    expect(s.takenOver, isEmpty);

    // A call the owner ended moves to the recent conversations.
    await t.runAsync(() async => s.liveTakeover(real, 'Keyhan'));
    s.liveCallGone(real);
    await settle();
    expect(find.byWidgetPredicate((w) => w is CallControls && w.room == real), findsNothing);
    expect(s.recentLive.first.room, real);
    expect(s.recentLive.first.lines.last.text, 'Call ended');
  });
}
