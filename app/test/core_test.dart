import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/services/catalog.dart';
import 'package:localailine/services/hardware.dart';
import 'package:localailine/services/ollama.dart';

Hardware hw({double ram = 32, double vram = 0, bool unified = true}) => Hardware(
    os: 'test', cpu: 'cpu', cores: 8, ramGb: ram, gpu: 'gpu', vramGb: vram, unifiedMemory: unified, freeDiskGb: 100);

void main() {
  late Db db;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ll_test');
    db = await Db.open(path: '${tmp.path}/t.db');
  });
  tearDown(() async {
    await db.raw.close();
    await tmp.delete(recursive: true);
  });

  group('passwords', () {
    test('hash verifies and rejects wrong password', () async {
      final h = await PasswordHasher.hash('correct horse battery');
      expect(h, startsWith('argon2id\$'));
      expect(await PasswordHasher.verify('correct horse battery', h), isTrue);
      expect(await PasswordHasher.verify('wrong password!!', h), isFalse);
    });
    test('same password gives different hashes (salted)', () async {
      expect(await PasswordHasher.hash('abcdefghijk'), isNot(await PasswordHasher.hash('abcdefghijk')));
    });
  });

  group('accounts', () {
    test('create owner, sign in, wrong password fails', () async {
      final auth = AuthService(db);
      expect(await auth.hasOwner(), isFalse);
      final u = await auth.createUser(name: 'Alex Morgan', username: 'Alex', password: 'correct-horse-42', role: Role.owner);
      expect(u.username, 'alex');
      expect(u.initials, 'AM');
      expect(await auth.hasOwner(), isTrue);
      final s = await auth.signIn('ALEX', 'correct-horse-42');
      expect(s.role, Role.owner);
      expect(() => auth.signIn('alex', 'nope-nope-nope'), throwsA(isA<AuthError>()));
      expect(() => auth.signIn('nobody', 'correct-horse-42'), throwsA(isA<AuthError>()));
    });
    test('validation', () async {
      final auth = AuthService(db);
      expect(() => auth.createUser(name: 'a', username: 'ok', password: 'short', role: Role.viewer), throwsA(isA<AuthError>()));
      expect(() => auth.createUser(name: 'a', username: 'bad name', password: 'longenough1', role: Role.viewer), throwsA(isA<AuthError>()));
      await auth.createUser(name: 'a', username: 'dup', password: 'longenough1', role: Role.viewer);
      expect(() => auth.createUser(name: 'b', username: 'dup', password: 'longenough1', role: Role.viewer), throwsA(isA<AuthError>()));
    });
    test('role permissions', () {
      expect(User(1, 'o', 'o', Role.owner).can(Perm.manageUsers), isTrue);
      expect(User(2, 'a', 'a', Role.admin).can(Perm.manageUsers), isFalse);
      expect(User(3, 'p', 'p', Role.operator).can(Perm.takeOver), isTrue);
      expect(User(4, 'v', 'v', Role.viewer).can(Perm.approve), isFalse);
    });
  });

  group('database', () {
    test('seeds defaults once', () async {
      await db.seedDefaults('Alex Morgan');
      await db.seedDefaults('Alex Morgan');
      expect(await db.count('agents'), 2);
      final ava = (await db.all('agents', orderBy: 'id')).first;
      expect(ava['name'], 'Ava');
      expect(ava['greeting'] as String, contains('Alex'));
      expect(await db.count('skills'), greaterThan(3));
    });
    test('settings round-trip', () async {
      await db.setSetting('k', 'v1');
      await db.setSetting('k', 'v2');
      expect(await db.setting('k'), 'v2');
      expect(await db.setting('missing'), isNull);
    });
    test('chats cascade-delete their messages', () async {
      final id = await db.insert('chats', {'title': 't', 'updated_at': 1});
      await db.insert('chat_messages', {'chat_id': id, 'role': 'user', 'content': 'hi', 'at': 1});
      await db.delete('chats', id);
      expect(await db.count('chat_messages'), 0);
    });
  });

  group('model fit', () {
    final catalog = Catalog.parse(File('assets/catalog/models.json').readAsStringSync());
    LlmEntry m(String id) => catalog.llm.firstWhere((e) => e.id == id);

    test('32 GB Apple Silicon: 8B great, 32B tight; 16 GB: 32B too large', () {
      final h = hw(ram: 32);
      expect(m('qwen3:8b').fitFor(h), Fit.great);
      expect(m('qwen3:32b').fitFor(h), Fit.tight);
      expect(m('qwen3:32b').fitFor(hw(ram: 16)), Fit.tooLarge);
      expect(catalog.recommend(h).id, 'qwen3:8b');
    });
    test('8 GB laptop gets a small model', () {
      final h = hw(ram: 8, unified: false);
      expect(m('qwen3:8b').fitFor(h), Fit.tooLarge);
      expect(catalog.recommend(h).params, lessThan(4));
    });
    test('choices: best first, then smarter and lighter options that fit', () {
      final c = catalog.choices(hw(ram: 18));
      expect(c.first.$2, 'Best for this computer');
      expect(c.first.$1.id, catalog.recommend(hw(ram: 18)).id);
      for (final (m, _) in c) {
        expect(m.fitFor(hw(ram: 18)), isNot(Fit.tooLarge));
      }
      expect(c.length, greaterThan(2));
      expect(c.any((x) => x.$1.slow), isFalse);
    });
    test('bestInstalled picks the strongest downloaded model that fits', () {
      expect(catalog.bestInstalled(hw(ram: 18), ['qwen2.5:0.5b', 'qwen3:4b-instruct']), 'qwen3:4b-instruct');
      // Thinking-only models are too slow for calls and are not auto-picked.
      expect(catalog.bestInstalled(hw(ram: 18), ['qwen2.5:0.5b', 'qwen3:4b']), 'qwen2.5:0.5b');
      expect(catalog.bestInstalled(hw(ram: 18), ['qwen3:4b']), 'qwen3:4b');
      expect(catalog.bestInstalled(hw(ram: 8, unified: false), ['qwen2.5:0.5b', 'qwen3:32b']), 'qwen2.5:0.5b');
      expect(catalog.bestInstalled(hw(), ['my-custom-model']), 'my-custom-model');
      expect(catalog.bestInstalled(hw(), []), isNull);
    });
    test('24 GB NVIDIA GPU fits 24B', () {
      final h = hw(ram: 64, vram: 24, unified: false);
      expect(m('mistral-small3.2:24b').fitFor(h), isNot(Fit.tooLarge));
    });
  });

  test('live Ollama chat (skipped when Ollama is not running)', () async {
    final o = Ollama();
    if (await o.version() == null) {
      markTestSkipped('Ollama not running');
      return;
    }
    final models = (await o.installed()).where((m) => !m.isEmbedding).toList();
    if (models.isEmpty) {
      markTestSkipped('No models installed');
      return;
    }
    // The small default model if it's there (a big one may take minutes just to load).
    final model = models.where((m) => m.name == 'qwen3:4b-instruct').firstOrNull ?? models.reduce((a, b) => a.sizeBytes < b.sizeBytes ? a : b);
    final String out;
    try {
      out = await o.chat(model.name, [ChatMessage('user', 'Reply with the single word: ready')]).join().timeout(const Duration(seconds: 90));
    } on TimeoutException {
      markTestSkipped('Ollama is too busy to answer right now');
      return;
    }
    expect(out.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
