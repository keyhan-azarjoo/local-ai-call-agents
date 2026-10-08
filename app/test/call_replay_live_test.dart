// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/agent_loop.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/ollama.dart';
import 'package:localailine/services/persona.dart';
import 'package:localailine/state/app_state.dart';

/// Real calls from 6 Oct, replayed with a real local model the way the voice path runs them.
/// LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/call_replay_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  const caller = '+447700900124';

  Future<({McpManager mcp, AppData data, List<ToolBinding> tools, AppsManager apps})> setUpApp() async {
    final tmp = Directory.systemTemp.createTempSync('replay');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final mcp = McpManager(db, openBrowser: (_) async {});
    final apps = AppsManager(db, mcp, ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    final id = await apps.createFromTemplate(appTemplates.first, name: 'Pasargad');
    final srv = (await mcp.servers()).firstWhere((s) => s.secret['role'] == 'customers');
    await mcp.connect(srv.id);
    final fresh = (await mcp.servers()).firstWhere((s) => s.id == srv.id);
    return (
      mcp: mcp,
      data: AppData(db, id, (await apps.app(id))!.spec),
      tools: [for (final t in fresh.tools) ToolBinding(serverId: fresh.id, serverName: fresh.name, tool: t, fnName: ToolBinding.safeName(fresh.name, t.name))],
      apps: apps,
    );
  }

  /// One spoken turn as the voice path does it: rules, calendar, no-repeat, caller number, follow-through.
  Future<String> turn(ToolLoop loop, McpManager mcp, List<ToolBinding> tools, String base, List<ChatMessage> convo) async {
    final used = <String>[];
    Future<({String text, bool isError})> run(ToolBinding b, Map<String, dynamic> args) async {
      if (RegExp(r'^(find|cancel)_my_').hasMatch(b.tool.name)) args = {...args, 'phone': caller};
      used.add('${b.tool.name}(${args.entries.map((e) => '${e.key}=${e.value}').join(', ')})'); print('    ~ ${used.last}');
      return mcp.call(b.serverId, b.tool.name, args);
    }

    final lastSaid = convo.lastWhere((m) => m.role == 'assistant', orElse: () => ChatMessage('assistant', '')).content;
    final msgs = [ChatMessage('system', '$base${AppState.calendar()} The number of the person on this call is $caller.${AppState.noRepeat(lastSaid)}'), ...convo];
    var reply = await loop.run(target: LocalTarget(model!, maxCtx: 16384), messages: msgs, tools: tools, approve: (_, _) async => false, runTool: run);
    if (AppState.unfinished(reply, usedTool: used.isNotEmpty, acted: used.any((u) => RegExp(r'^(add_|cancel_my_)').hasMatch(u)))) {
      final more = await loop.run(
          target: LocalTarget(model, maxCtx: 16384),
          messages: [...msgs, ChatMessage('assistant', reply), ChatMessage('user', '(Go ahead: use your tools now and tell me the result in one or two sentences. Don\'t say you will check again.)')],
          tools: tools,
          approve: (_, _) async => false,
          runTool: run);
      reply = '$reply [then] $more';
    }
    // The safety net (as on a real call): said it's booked, or promised to, and saved nothing.
    final asked = convo.where((m) => m.role == 'user').map((m) => m.content).join(' ');
    if (!used.any((u) => u.startsWith('add_')) && (RegExp(r'\b(confirmed|booked|reserved)\b', caseSensitive: false).hasMatch(reply) || AppState.promisesAction(reply)) &&
        RegExp(r'\bbook', caseSensitive: false).hasMatch(asked) && !RegExp(r'cancel', caseSensitive: false).hasMatch(asked)) {
      final add = tools.firstWhere((t) => t.tool.name == 'add_reservations');
      final c = await AppState.commitWith(loop, LocalTarget(model, maxCtx: 16384), add, [...convo, ChatMessage('assistant', reply)], (args) => run(add, args), callerNumber: caller);
      reply = '$reply [net: ${c == null ? 'no call' : c.ok ? 'saved' : 'failed: ${c.text}'}]';
    }
    print('  tools: ${used.join(' · ')}\n  AI: $reply');
    return reply;
  }

  test('18:47 call: book for tomorrow, then switch to table 5', () async {
    final a = await setUpApp();
    final base = '${Persona.callerSystem({'name': 'Ava', 'instructions': 'You answer phone calls for Pasargad restaurant.'})} '
        'This is a live voice conversation: answer in one to three short spoken sentences.${AppState.appRulesText(a.tools)}';
    final convo = [ChatMessage('assistant', 'Hi, thanks for calling Pasargad. How can I help?')];
    final loop = ToolLoop();
    for (final heard in [
      'Hello, I want to book a table for tomorrow.',
      'My name is Kehan, it\'s for two people, tomorrow at 5 p.m. No special needs.',
      'Could I have table 5 instead?',
      'Yes, book it.',
    ]) {
      print('CALLER: $heard');
      convo
        ..add(ChatMessage('user', heard))
        ..add(ChatMessage('assistant', await turn(loop, a.mcp, a.tools, base, convo)));
    }
    final rows = await a.data.list('reservations', manager: true);
    print('BOOKINGS: $rows');
    final tomorrow = DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    expect(rows.where((r) => r['date'] == tomorrow && r['time'] == '17:00'), isNotEmpty);
    await a.apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 10)));

  test('18:44 call: what time is my booking, then cancel it', () async {
    final a = await setUpApp();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await a.data.add('reservations', {'name': 'Keyhan', 'phone': '07700 900124', 'date': today, 'time': '20:30', 'guests': 2}, via: 'website');
    final base = '${Persona.outboundSystem('Ava', 'Keyhan', 'Keyhan', 'ask for confirmation for the reservation')} '
        'This is a live voice conversation: answer in one to three short spoken sentences.${AppState.appRulesText(a.tools)}';
    final convo = [ChatMessage('assistant', 'Hello, this is Ava, an AI assistant calling on behalf of Keyhan. I just wanted to confirm your reservation for tonight.')];
    final loop = ToolLoop();
    final replies = <String>[];
    for (final heard in ['What time is my booking?', 'No, cancel it.', 'My name is Keyhan and my number is 07700 900124.', 'Yes, cancel it please.']) {
      print('PERSON: $heard');
      final r = await turn(loop, a.mcp, a.tools, base, convo..add(ChatMessage('user', heard)));
      replies.add(r);
      convo.add(ChatMessage('assistant', r));
    }
    final r = (await a.data.list('reservations', manager: true)).first;
    print('BOOKING NOW: $r');
    expect(replies.first, anyOf(contains('20:30'), contains('8:30')), reason: 'the real time, looked up');
    expect(r['status'], 'Cancelled');
    await a.apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 10)));
}
