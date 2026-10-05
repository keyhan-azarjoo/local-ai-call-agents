import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/knowledge/chunker.dart';
import 'package:localailine/services/knowledge/extract.dart';
import 'package:localailine/services/knowledge/knowledge.dart';
import 'package:localailine/ui/pages/knowledge_page.dart' show skillFrom;

// ignore_for_file: avoid_print
const pdf = '../skills/restaurant-skill.pdf';
const md = '../skills/restaurant-skill.md';

Future<void> settle(KnowledgeService k, int id, Db db) async {
  for (var i = 0; i < 600; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final s = (await db.all('knowledge', where: 'id = ?', args: [id])).first['status'];
    if (k.progress.isEmpty && (s == 'ready' || s == 'error' || s == 'empty')) return;
  }
}

void main() {
  late Db db;
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ll_kn');
    db = await Db.open(path: '${tmp.path}/k.db');
  });
  tearDown(() async {
    await db.raw.close();
    await tmp.delete(recursive: true);
  });

  test('chunker keeps headings and table rows whole', () {
    final chunks = Chunker(target: 200).chunk([
      Section('# Menu\nIntro line.\n\n## Mains\nBurger is great.\n\nFish is fresh.'),
      Section('Dish: Burger; Price: £15.50\nDish: Fish; Price: £16.00', table: true),
    ]);
    expect(chunks.any((c) => c.heading == 'Mains' && c.text.contains('Burger')), isTrue);
    expect(chunks.last.text, contains('Price: £16.00'));
  });

  test('skill name and instructions are found in both PDF and Markdown', () async {
    if (!File(md).existsSync()) return markTestSkipped('skill files not built');
    for (final f in [md]) { // PDF is covered by integration_test/knowledge_app_test.dart (PDFium ships with the app)
      final text = (await TextExtractor.extract(f)).map((s) => s.text).join('\n\n');
      final (name, instructions, _) = skillFrom(text, 'x');
      print('$f → name="$name" instructions=${instructions.length} chars; starts "${instructions.substring(0, 60)}"');
      expect(name, contains('Restaurant Assistant Skill'));
      expect(instructions, contains('phone voice of The Copper Kettle'));
      expect(instructions, contains('£20'));
      expect(instructions, isNot(contains('Fish & chips'))); // menu stays in knowledge, not in the prompt
    }
  });

  test('index the skill, search fast and accurately, follow file changes', () async {
    if (!File(md).existsSync()) return markTestSkipped('skill files not built');
    final k = KnowledgeService(db);
    final sw = Stopwatch()..start();
    final id = await k.addSource(File(md).absolute.path, scope: 'all');
    await settle(k, id, db);
    final row = (await db.all('knowledge')).first;
    print('INDEXED ${row['files']} file, ${row['chunks']} passages in ${sw.elapsedMilliseconds} ms; vectors: ${k.chunkCount}; embedError: ${k.embedError}');
    expect(row['status'], 'ready');

    final checks = {
      'Do you have vegan food?': 'VG',
      'how much is the burger': '15.50',
      'delivery fee for RV3': '3.95',
      'what is the refund limit': '£20',
      'are dogs allowed': 'terrace',
      'parking near the restaurant': 'Mill Lane',
      'chicken satay allergy': 'peanuts',
    };
    var hitsOk = 0;
    for (final e in checks.entries) {
      final r = await k.search(e.key, k: 3);
      final ok = r.hits.any((h) => h.text.toLowerCase().contains(e.value.toLowerCase()));
      if (ok) hitsOk++;
      print('  ${ok ? 'OK ' : 'MISS'} ${r.ms} ms  "${e.key}" → ${r.hits.isEmpty ? '-' : r.hits.first.where}');
    }
    expect(hitsOk, greaterThanOrEqualTo(6));

    // A folder: add, change, delete — the index follows.
    final dir = Directory('${tmp.path}/docs')..createSync();
    final f = File('${dir.path}/hours.md')..writeAsStringSync('# Opening hours\nWe open at 9am on Sundays.');
    final fid = await k.addSource(dir.path, scope: 'all');
    await settle(k, fid, db);
    expect((await k.search('Sunday opening time', k: 2)).hits.first.text, contains('9am'));
    await Future.delayed(const Duration(milliseconds: 1100)); // mtime resolution
    f.writeAsStringSync('# Opening hours\nWe open at 11am on Sundays.');
    k.enqueue(fid); // the folder watcher does this automatically in the app
    await settle(k, fid, db);
    final after = (await k.search('Sunday opening time', k: 2)).hits.first.text;
    print('  CHANGED → $after');
    expect(after, contains('11am'));
    f.deleteSync();
    k.enqueue(fid);
    await settle(k, fid, db);
    expect(await db.count('kn_chunks', where: 'source_id = ?', args: [fid]), 0);
    k.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
