import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localailine/main.dart';
import 'package:localailine/state/app_state.dart';
import 'package:provider/provider.dart';

/// Drives the real app end to end on this computer, against the real local
/// Ollama, with a throwaway database.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $f');
  }

  late AppState state;

  Future<void> tapText(WidgetTester t, String text) async {
    // Snackbars float over the bottom of the window; clear them so taps land.
    state.messenger.currentState?.removeCurrentSnackBar();
    await t.pump();
    final f = find.text(text).last;
    await t.ensureVisible(f);
    await t.tap(f);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('first run → talk → make a call → phone line → users → sign out/in', (t) async {
    final dir = await Directory.systemTemp.createTemp('ll_it');
    state = AppState(dbPath: '${dir.path}/it.db')..speakReplies = false;
    await state.init();
    await t.binding.setSurfaceSize(const Size(1440, 1000));
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const LocalAILineApp()));
    await settle(t);

    // ---- Setup wizard ----
    await waitFor(t, find.text('Start setup'));
    await tapText(t, 'Start setup');
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Keyhan Azarjoo');
    await t.enterText(fields.at(1), 'keyhan');
    await t.enterText(fields.at(2), 'test-password-123');
    await tapText(t, 'Create account');
    await waitFor(t, find.text('Set up the AI'), seconds: 20);
    // Real hardware + engine check.
    await waitFor(t, find.textContaining('GB memory'), seconds: 30);
    expect(state.hardware, isNotNull);
    debugPrint('HW: ${state.hardware!.cpu} ${state.hardware!.ramGb.toStringAsFixed(0)} GB, engine ${state.ollamaVersion}, model ${state.llmModel}');
    await tapText(t, 'Continue');
    await tapText(t, 'Skip for now');
    await tapText(t, 'Go to Home');
    await waitFor(t, find.text('Latest calls'));
    expect(state.user?.username, 'keyhan');

    // ---- Talk to Ava (caller) ----
    await tapText(t, 'Talk to Ava');
    await waitFor(t, find.textContaining('How can I help'));
    if (state.llmReady) {
      await t.enterText(find.byType(TextField).last, 'Hi, can I leave a message for Keyhan?');
      await tapText(t, 'Send');
      await waitFor(t, find.textContaining('s to first word'), seconds: 90);
      debugPrint('Caller reply OK with ${state.llmModel}');
      await tapText(t, 'Save to Calls');
      expect(await state.db.count('calls'), 1);

      // ---- Talk to Ava (owner instructions) ----
      await tapText(t, 'Give instructions');
      await waitFor(t, find.textContaining('What would you like me to do'));
      state.messenger.currentState?.removeCurrentSnackBar();
      await t.pump();
      // enterText does not reach this field after the first exchange in the
      // test harness, so set the controller directly; the send path is the same.
      (find.byType(TextField).last.evaluate().first.widget as TextField).controller!.text =
          'Call Riverside Dental on +44 20 7946 0011 and move my check-up to next week.';
      await t.pump();
      debugPrint('INPUT: "${(find.byType(TextField).last.evaluate().first.widget as TextField).controller?.text}" fields=${find.byType(TextField).evaluate().length} send=${find.text('Send').evaluate().length}');
      await tapText(t, 'Send');
      try {
        await waitFor(t, find.textContaining('s to first word'), seconds: 60);
      } on TestFailure {
        for (final w in find.byType(SelectableText).evaluate()) {
          debugPrint('TURN: ${(w.widget as SelectableText).data}');
        }
        rethrow;
      }
      debugPrint('Owner reply received; call task suggested: ${find.text('Review call').evaluate().isNotEmpty}');
    } else {
      debugPrint('No LLM ready — skipped chat checks');
    }

    // ---- Make a call ----
    await tapText(t, 'Make a call');
    await waitFor(t, find.text('Call details'));
    final callFields = find.byType(TextField);
    await t.enterText(callFields.at(1), 'Riverside Dental');
    await t.enterText(callFields.at(2), '+44 20 7946 0011');
    await t.enterText(callFields.at(3), 'Move my check-up to next week, mornings only.');
    await tapText(t, 'Start call');
    await waitFor(t, find.text('Connect a phone line to call'));
    await tapText(t, 'Keep in queue');
    await waitFor(t, find.text('Waiting for phone line'));

    // ---- Phone line ----
    await tapText(t, 'Phone line');
    await tapText(t, 'Add phone line');
    await tapText(t, 'Other SIP provider');
    final lf = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await t.enterText(lf.at(0), 'sip.example.com');
    await t.enterText(lf.at(1), 'user1');
    await t.enterText(lf.at(2), 'secret');
    await t.enterText(lf.at(3), '+441234567890');
    await tapText(t, 'Save line');
    await waitFor(t, find.text('+441234567890 · Other SIP provider'));

    // ---- My assistant: edit greeting ----
    await tapText(t, 'My assistant');
    await waitFor(t, find.text('First thing callers hear'));
    await t.enterText(find.byType(TextField).at(1), 'Hello, Keyhan’s phone — Ava speaking.');
    await tapText(t, 'Save changes');
    final ava = (await state.db.all('agents', orderBy: 'id')).first;
    expect(ava['greeting'], 'Hello, Keyhan’s phone — Ava speaking.');

    // ---- All features ----
    await state.setAdvanced(true);
    await settle(t);
    await tapText(t, 'Language models');
    await waitFor(t, find.text('Loaded now'));
    await tapText(t, 'Users & access');
    await tapText(t, 'Add user');
    final uf = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await t.enterText(uf.at(0), 'Maya Rahimi');
    await t.enterText(uf.at(1), 'maya');
    await t.enterText(uf.at(2), 'maya-password-1');
    await tapText(t, 'Add user');
    await waitFor(t, find.text('Maya Rahimi'));
    await tapText(t, 'Activity & logs');
    await waitFor(t, find.text('Added user maya as operator'));

    // ---- Sign out / in ----
    await state.signOut();
    await settle(t);
    await waitFor(t, find.text('Sign in'));
    final sf = find.byType(TextField);
    await t.enterText(sf.at(0), 'maya');
    await t.enterText(sf.at(1), 'maya-password-1');
    await tapText(t, 'Sign in');
    await waitFor(t, find.text('Latest calls'));
    expect(state.user?.username, 'maya');
    debugPrint('END-TO-END OK');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
