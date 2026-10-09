// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/agent_loop.dart';
import 'package:localailine_apps/app_data.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_apps/apps_manager.dart';
import 'package:localailine_core/services/mcp/mcp_manager.dart';
import 'package:localailine_core/services/ollama.dart';
import 'package:localailine_core/services/persona.dart';
import 'package:localailine/state/app_state.dart';

/// The caller's real conversation (6 Oct), replayed with a real local model and the restaurant app.
/// LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/call_booking_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  test('a phone booking lands in the app', () async {
    final tmp = Directory.systemTemp.createTempSync('callbook');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final mcp = McpManager(db, openBrowser: (_) async {});
    final apps = AppsManager(db, mcp, ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    final id = await apps.createFromTemplate(appTemplates.first, name: 'Pasargad');
    final srv = (await mcp.servers()).firstWhere((s) => s.secret['role'] == 'customers');
    await mcp.connect(srv.id);
    final fresh = (await mcp.servers()).firstWhere((s) => s.id == srv.id);
    final tools = [for (final t in fresh.tools) ToolBinding(serverId: fresh.id, serverName: fresh.name, tool: t, fnName: ToolBinding.safeName(fresh.name, t.name))];
    final today = DateTime.now();
    final system = '${Persona.callerSystem({'name': 'Sam', 'instructions': 'You are Sam, who takes bookings and orders.'})} '
        'This is a live voice conversation: answer in one to three short spoken sentences. Today is ${today.toIso8601String().substring(0, 10)} (${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][today.weekday - 1]}).'
        '${AppEngine.appRulesText(tools)}';
    final convo = [ChatMessage('system', system), ChatMessage('assistant', 'Hi, thanks for calling Pasargad. How can I help?')];
    final loop = ToolLoop();
    for (final heard in [
      'I want to see that can you book a table for me for today?',
      'I wanted for like 7pm, two people.',
      'Thanks, for two people, my name is Kei Han and my phone number is 07700 900124.',
      'Yeah, that\'s correct.',
      'Did you book it?',
    ]) {
      convo.add(ChatMessage('user', heard));
      final used = <String>[];
      final reply = await loop.run(
        target: LocalTarget(model!, maxCtx: 8192),
        messages: List.of(convo),
        tools: tools,
        approve: (_, _) async => false,
        runTool: (b, args) async {
          used.add('${b.tool.name}(${args.entries.map((e) => '${e.key}=${e.value}').join(', ')})');
          return mcp.call(b.serverId, b.tool.name, args);
        },
      );
      // The safety net from the voice path.
      var net = '';
      if (!used.any((u) => u.startsWith('add_'))) {
        final tool = tools.firstWhere((t) => t.tool.name == 'add_reservations');
        if (RegExp(r'\b(confirmed|saved|booked|placed|reserved)\b', caseSensitive: false).hasMatch(reply)) {
          final c = await AppEngine.commitWith(loop, LocalTarget(model, maxCtx: 8192), tool, [...convo, ChatMessage('assistant', reply)], (args) {
            used.add('NET add_reservations(${args.entries.map((e) => '${e.key}=${e.value}').join(', ')})');
            return mcp.call(tool.serverId, tool.tool.name, args);
          });
          net = c == null ? ' [net: no call]' : ' [net: ${c.ok ? 'saved' : 'failed: ${c.text}'}]';
        }
      }
      print('CALLER: $heard\n  tools: ${used.join(' · ')}\n  SAM: $reply$net');
      convo.add(ChatMessage('assistant', reply));
    }
    final a = (await apps.app(id))!;
    final bookings = await AppData(db, id, a.spec).list('reservations', manager: true);
    print('BOOKINGS: $bookings');
    expect(bookings, isNotEmpty);
    await apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 10)));
}
