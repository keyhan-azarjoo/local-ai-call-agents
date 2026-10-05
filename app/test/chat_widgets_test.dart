import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/theme/tokens.dart';
import 'package:localailine/ui/pages/chat_page.dart';

String note({bool ok = true, bool denied = false, String result = '{"id": "1"}'}) =>
    jsonEncode({'server': 'Shop', 'tool': 'list_users', 'args': {}, 'ok': ok, 'denied': denied, 'result': result});

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('tool notes draw and expand without errors ($b)', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(b),
        home: Scaffold(
          body: ListView(children: [
            ToolNote(note()),
            ToolNote(note(ok: false, result: 'Tool error (500): boom.')),
            ToolNote(note(ok: false, denied: true)),
            ToolNote(note(ok: false, result: 'The tool was not called because of its inputs: x')),
            const ToolNote('not json'),
          ]),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.textContaining('Used Shop'), findsOneWidget);
      expect(find.textContaining('Error from Shop'), findsOneWidget);
      expect(find.textContaining('Not allowed'), findsOneWidget);
      expect(find.textContaining('Fixing inputs'), findsOneWidget);
      await t.tap(find.textContaining('Used Shop'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('Result:'), findsOneWidget);
    });
  }
}
