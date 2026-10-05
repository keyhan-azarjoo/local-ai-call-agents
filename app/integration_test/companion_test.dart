import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localailine/main.dart';
import 'package:localailine/state/app_state.dart';
import 'package:provider/provider.dart';

/// Run on a phone/simulator while the main computer runs LocalAILine with
/// LOCALAILINE_DEV_PAIRCODE=246810 and LOCALAILINE_DEV_RING=1.
/// Host address comes from --dart-define=HOST=ip:port (default 127.0.0.1:7420).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const hostAddr = String.fromEnvironment('HOST', defaultValue: '127.0.0.1:7420');

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $f');
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.tap(find.text(text).last);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('phone pairs with the computer, sees status, chats, answers a ring', (t) async {
    final dir = await Directory.systemTemp.createTemp('ll_phone');
    final state = AppState(dbPath: '${dir.path}/phone.db');
    await state.init();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const LocalAILineApp()));

    await waitFor(t, find.text('Connect to your LocalAILine computer'));
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), hostAddr);
    await t.enterText(fields.at(1), '246810');
    await tap(t, 'Connect');
    try {
      await waitFor(t, find.textContaining(RegExp('connected to', caseSensitive: false)), seconds: 20);
    } on TestFailure {
      for (final w in find.byType(Text).evaluate()) {
        debugPrint('TEXT: ${(w.widget as Text).data}');
      }
      rethrow;
    }
    expect(state.gate, Gate.companion);
    await waitFor(t, find.textContaining('answering'));
    debugPrint('PAIRED with ${state.remoteName}');

    // Spoken turn through the computer (text in, Ava's voice back).
    final r = await state.remote!.post('talk', {'text': 'Hi, is anyone there?'}) as Map;
    expect('${r['reply']}', isNotEmpty);
    expect(r['audio'], isNotNull, reason: 'the computer should send Ava’s voice');
    debugPrint('TALK reply: ${r['reply']} (${(r['audio'] as String).length} b64 chars of audio)');

    // Chat through the computer's AI.
    await tap(t, 'Chat');
    await t.enterText(find.byType(TextField).last, 'Reply with one word: hello');
    await tap(t, 'Send');
    await waitFor(t, find.textContaining(RegExp('hello', caseSensitive: false)), seconds: 90);
    debugPrint('CHAT ok');

    // The computer test-rings shortly after we connect.
    await waitFor(t, find.text('Answer here'), seconds: 40);
    debugPrint('RING received');
    await tap(t, 'Answer here');
    expect(state.incoming, isNull);
    debugPrint('PHONE E2E OK');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
