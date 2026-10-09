import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_ui/app_model.dart';
import 'package:localailine_ui/theme/tokens.dart';
import 'package:localailine_ui/ui/pages/live_calls.dart';
import 'package:localailine_ui/ui/pages/main_pages.dart';
import 'package:provider/provider.dart';

/// The app with the phone side recorded instead of done: nothing is built, started or rung.
class _State extends AppState {
  _State({super.dbPath});
  final tested = <Map<String, dynamic>>[];
  final connected = <int>[];
  final answers = <(int, AnswerMode, int?)>[];
  final released = <String>[];
  ({bool ok, String result}) testAnswer = (ok: false, result: 'wrong username or password (the provider said 403 Forbidden)');

  @override
  Future<({bool ok, String result})> testSipLine(Map<String, dynamic> cfg, {int? lineId}) async {
    tested.add(cfg);
    return testAnswer;
  }

  @override
  Future<String> connectLine(int lineId) async {
    connected.add(lineId);
    return 'Signing in to your provider…';
  }

  @override
  Future<String> setLineAnswer(int lineId, AnswerMode mode, {int? ringSeconds}) async {
    answers.add((lineId, mode, ringSeconds));
    return 'Saved.';
  }

  @override
  void releaseCall(String room, {String go = 'ai'}) => released.add(room);
}

void main() {
  late _State s;

  Future<void> open(WidgetTester t, Widget child, {Size size = const Size(1100, 1400)}) async {
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('lines_ui');
      s = _State(dbPath: '${tmp.path}/t.db');
      s.db = await Db.open(path: '${tmp.path}/t.db');
      addTearDown(() async {
        await s.db.raw.close();
        tmp.deleteSync(recursive: true);
      });
    });
    await t.pumpWidget(ListenableProvider<AppModel>.value(
      value: s,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child))),
    ));
    await t.pump();
  }

  Future<List<Map<String, Object?>>> lines(WidgetTester t) async => (await t.runAsync(() => s.db.all('lines', orderBy: 'id')))!;

  /// Lets database work (real I/O) finish, then redraws.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('add my own number: a preset fills in the settings, the test says why it failed, save connects it', (t) async {
    await open(t, Builder(builder: (c) => TextButton(onPressed: () => showLineDialog(c), child: const Text('open'))), size: const Size(1100, 2200));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // The new line type is the first choice.
    expect(find.text('Add phone line'), findsOneWidget);
    expect(find.text('My number, through my provider'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Who takes calls'), findsOneWidget);

    // Pick a provider: its usual settings, and "check them".
    await t.tap(find.text('Any SIP provider'));
    await t.pumpAndSettle();
    await t.tap(find.text('sipgate (UK)').last);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('sip-domain'))).controller!.text, 'sipgate.co.uk');
    expect(t.widget<TextField>(find.byKey(const ValueKey('sip-port'))).controller!.text, '5060');
    expect(find.textContaining('check them with your provider'), findsOneWidget);

    // Missing details are named before anything is tried.
    await t.tap(find.text('Test connection'));
    await t.pump();
    expect(find.text('Add your phone number.'), findsOneWidget);
    expect(s.tested, isEmpty);

    await t.enterText(find.byKey(const ValueKey('sip-number')), '+44 7700 900123');
    await t.enterText(find.byKey(const ValueKey('sip-username')), '1234567e0');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('sip-password')), matching: find.byType(TextField)), 'pw');
    await t.tap(find.text('Test connection'));
    await settle(t);
    expect(s.tested.single, containsPair('domain', 'sipgate.co.uk'));
    expect(s.tested.single, containsPair('transport', 'tcp'));
    expect(find.textContaining('wrong username or password'), findsOneWidget);

    s.testAnswer = (ok: true, result: 'Signed in to your provider: the details work.');
    await t.tap(find.text('Test connection'));
    await settle(t);
    expect(find.text('Signed in to your provider: the details work.'), findsOneWidget);

    // Who takes calls: ring me, then the AI after 30 seconds.
    await t.tap(find.text('Ring me, then the AI'));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('ring-seconds')), '30');
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.text('Save line'));
    await settle(t);
    final saved = (await lines(t)).single;
    expect(saved['provider'], 'sip');
    expect(saved['number'], '+447700900123');
    final cfg = jsonDecode('${saved['config']}') as Map<String, dynamic>;
    expect(cfg, containsPair('domain', 'sipgate.co.uk'));
    expect(cfg, containsPair('username', '1234567e0'));
    expect(cfg, containsPair('password', 'pw'));
    expect(cfg, containsPair('preset', 'sipgate_uk'));
    expect(LineAnswer.of(cfg).mode, AnswerMode.ringThenAi);
    expect(LineAnswer.of(cfg).ringSeconds, 30);
    expect(s.connected, [saved['id']]);
    expect(find.text('Add phone line'), findsNothing); // (the dialog closed)
  });

  testWidgets('edit my own number: the password can be left empty to keep it', (t) async {
    await open(t, const SizedBox(), size: const Size(1100, 2200));
    final id = (await t.runAsync(() => s.db.insert('lines', {
          'provider': 'sip',
          'label': 'My number',
          'number': '+447700900123',
          'config': jsonEncode({'number': '+447700900123', 'domain': 'sip.example.com', 'username': 'u1', 'password': 'old-secret', 'transport': 'tls'}),
          'status': 'saved',
        })))!;
    final row = (await lines(t)).single;
    await t.pumpWidget(ListenableProvider<AppModel>.value(
      value: s,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showLineDialog(c, line: row), child: const Text('edit'))))),
    ));
    await t.tap(find.text('edit'));
    await t.pumpAndSettle();
    expect(find.text('Edit phone line'), findsOneWidget);
    expect(find.text('Twilio'), findsNothing); // (the type stays)
    expect(t.widget<TextField>(find.byKey(const ValueKey('sip-domain'))).controller!.text, 'sip.example.com');
    expect(find.text('Leave empty to keep the saved password.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('sip-domain')), 'sip2.example.com');
    await t.tap(find.text('Save changes'));
    await settle(t);
    final cfg = jsonDecode('${(await lines(t)).single['config']}') as Map<String, dynamic>;
    expect(cfg['domain'], 'sip2.example.com');
    expect(cfg['password'], 'old-secret');
    expect(s.connected, [id]);
  });

  testWidgets('the mode picker: four clear choices, seconds only for the ringing ones, checked as typed', (t) async {
    final got = <LineAnswer>[];
    await open(t, AnswerModePicker(value: const LineAnswer(AnswerMode.ai), onChanged: got.add));
    for (final m in AnswerMode.values) {
      expect(find.text(m.label), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('ring-seconds')), findsNothing);
    expect(find.text('The AI answers every call.'), findsOneWidget);

    await t.tap(find.text('Ring me'));
    await t.pump();
    expect(got.last.mode, AnswerMode.ring);
    expect(got.last.ringSeconds, 20);
    expect(find.text('Ring for'), findsOneWidget);
    expect(find.textContaining('the AI takes a message'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('ring-seconds')), '3');
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Choose between 5 and 120 seconds.'), findsOneWidget);
    expect(got, hasLength(1)); // (nothing sent while it's wrong)

    await t.enterText(find.byKey(const ValueKey('ring-seconds')), '45');
    await t.pump(const Duration(milliseconds: 300));
    expect(got, hasLength(1)); // (not while typing)
    await t.pump(const Duration(seconds: 1));
    expect(got.last.ringSeconds, 45);

    await t.tap(find.text('Ring me, then the AI'));
    await t.pump();
    expect(got.last.mode, AnswerMode.ringThenAi);
    expect(got.last.ringSeconds, 45);
    expect(find.text('The AI answers after'), findsOneWidget);

    await t.tap(find.text('Off'));
    await t.pump();
    expect(got.last.mode, AnswerMode.off);
    expect(find.byKey(const ValueKey('ring-seconds')), findsNothing);
    expect(find.text('Calls on this line are not answered here.'), findsOneWidget);
  });

  testWidgets('the Phone line page: my number\'s state with the reason, and who takes calls', (t) async {
    await open(t, const LinesPage());
    final id = (await t.runAsync(() => s.db.insert('lines', {
          'provider': 'sip',
          'label': 'My number',
          'number': '+447700900123',
          'config': jsonEncode({'number': '+447700900123', 'domain': 'sip.example.com', 'username': 'u1', 'password': 'p'}),
          'status': 'saved',
        })))!;
    s.sipStatus[id] = const SipLineStatus('failed', 'wrong username or password');
    s.refresh();
    await settle(t);
    expect(find.text('Sign-in failed'), findsOneWidget);
    expect(find.text('Couldn’t sign in: wrong username or password'), findsOneWidget);
    expect(find.text('Who takes calls'), findsOneWidget);

    await t.tap(find.text('Off'));
    await settle(t);
    expect(s.answers.single, (id, AnswerMode.off, 20));

    s.sipStatus[id] = const SipLineStatus('registered');
    s.refresh();
    await settle(t);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('a call ringing you: Answer, or let the AI answer', (t) async {
    await open(t, const LiveCallsPanel(always: true));
    const room = 'pstn-in-3-_+447700900555_abc';
    s.liveCalls[room] = (agent: 'ringing', caller: 'listening', number: '+447700900555', name: '', at: DateTime.now());
    s.ringing[room] = (line: 'My number +447700900123', number: '+447700900555', until: DateTime.now().add(const Duration(seconds: 20)));
    s.refresh();
    await settle(t);
    expect(find.text('ringing you'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Take over'), findsNothing);
    expect(find.textContaining('Ringing you. Answer to talk'), findsOneWidget);
    await t.tap(find.text('Let the AI answer'));
    await t.pump();
    expect(s.released, [room]);

    // Once answered, the usual controls come back.
    s.ringing.remove(room);
    s.refresh();
    await settle(t);
    expect(find.text('Take over'), findsOneWidget);
    expect(find.text('Let the AI answer'), findsNothing);
  });
}
