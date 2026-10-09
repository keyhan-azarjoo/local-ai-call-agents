import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localailine_core/services/agent_loop.dart';
import 'package:localailine_core/services/auth.dart';
import 'package:localailine_core/services/knowledge/extract.dart';
import 'package:localailine_core/services/ollama.dart';
import 'package:localailine_core/services/persona.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/ui/pages/knowledge_page.dart' show skillFrom;

// ignore_for_file: avoid_print
/// Adds the restaurant PDF as a skill (like "Add skill") and asks Ava real calls.
/// Needs Ollama with qwen3:4b-instruct and embeddinggemma.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('restaurant skill from PDF answers calls', (t) async {
    final pdf = '${Platform.environment['HOME']}/Downloads/restaurant-skill.pdf';
    if (!File(pdf).existsSync()) return;
    final dir = await Directory.systemTemp.createTemp('ll_kapp');
    final s = AppState(dbPath: '${dir.path}/a.db');
    await s.init();
    await s.host?.stop();
    final u = await s.auth.createUser(name: 'Owner', username: 'owner', password: 'password-123', role: Role.owner);
    await s.completeSetup(u);
    await s.host?.stop();
    await s.setLlmModel(const String.fromEnvironment('MODEL', defaultValue: 'qwen3:4b-instruct'), manual: true);
    await s.refreshEngine();
    print('MODEL ${s.llmModel}');

    // Same steps as the "Add skill from a document" button.
    final sw = Stopwatch()..start();
    final text = (await TextExtractor.extract(pdf)).map((x) => x.text).join('\n\n');
    final (name, instructions, summary) = skillFrom(text, 'restaurant-skill');
    final src = await s.knowledge.addSource(pdf, scope: 'all', name: 'Skill: $name');
    await s.db.insert('skills', {'name': name, 'description': summary, 'instructions': instructions, 'source_id': src, 'enabled': 1});
    for (var i = 0; i < 600; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final st = (await s.db.all('knowledge', where: 'id = ?', args: [src])).first;
      if (s.knowledge.progress.isEmpty && st['status'] == 'ready') break;
    }
    final row = (await s.db.all('knowledge', where: 'id = ?', args: [src])).first;
    print('PDF SKILL "$name": ${row['chunks']} passages, instructions ${instructions.length} chars, ready in ${sw.elapsedMilliseconds} ms');
    expect(row['status'], 'ready');
    expect(name, startsWith('Restaurant Assistant Skill'));
    expect((row['chunks'] as int) > 8, isTrue);

    for (final r in await s.db.raw.rawQuery("SELECT text FROM kn_chunks WHERE text LIKE '%burger%' OR text LIKE '%Zone B%'")) {
      print('CHUNK>>> ${(r['text'] as String).replaceAll('\n', ' ⏎ ')}');
    }
    if (const bool.fromEnvironment('CHUNKS_ONLY')) return;
    if (const bool.fromEnvironment('QUOTE_ONLY')) {
      final lines = await s.knowledge.priceLines({src});
      print('PRICE LINES ${lines.length}:\n${lines.take(40).join('\n')}');
      for (final q in ['Hi, can I order two fish and chips for delivery to RV3 4AB?', 'Can I get one burger and two cokes for collection?']) {
        final quote = await OrderQuote.quote(s.toolLoop.client, s.modelTarget as LocalTarget, [ChatMessage('user', q)], lines);
        print('QUOTE for "$q": $quote');
      }
      return;
    }
    final agent = (await s.db.all('agents', where: "handles = 'incoming'", orderBy: 'id')).first;
    final calls = {
      'Hi, can I order two fish and chips for delivery to RV3 4AB?': ['35.95'],
      'Can I get one burger and two cokes for collection?': ['21.50', 'twenty-one pounds fifty'],
      'Do you have anything vegan?': ['tofu', 'risotto', 'hummus'],
      'Part of my order was missing yesterday, a side of fries. Can I get a refund?': ['refund', 'order', 'name', 'approve'],
      'Can I just read you my card number?': ['link'],
      'I am allergic to peanuts. Is the chicken satay ok?': ['peanut'],
      'What time do you close on Saturday?': ['23', '11'],
    };
    var good = 0;
    for (final e in calls.entries) {
      final msgs = [...Persona.callerStart(agent), ChatMessage('user', e.key)];
      final t0 = Stopwatch()..start();
      Duration? first;
      final used = <String>[];
      final a = await s.agentReply(msgs, scopes: {'all'}, approve: (_, _) async => false,
          onText: (x) => first ??= t0.elapsed, onEvent: (e) => used.add('${e.binding.tool.name}(${e.args.values.join(',')})=${e.result}'));
      final ok = e.value.any((w) => a.toLowerCase().contains(w.toLowerCase()));
      if (ok) good++;
      print('${ok ? 'OK ' : '?? '} tools $used, first word ${first?.inMilliseconds} ms, total ${t0.elapsedMilliseconds} ms\n   Q: ${e.key}\n   A: ${a.replaceAll('\n', ' ')}');
    }
    print('GOOD $good/${calls.length}');
    expect(good, greaterThanOrEqualTo(5));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
