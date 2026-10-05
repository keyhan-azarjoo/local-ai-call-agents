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
      final u = await auth.createUser(name: 'Keyhan Azarjoo', username: 'Keyhan', password: 'supersecret1', role: Role.owner);
      expect(u.username, 'keyhan');
      expect(u.initials, 'KA');
      expect(await auth.hasOwner(), isTrue);
      final s = await auth.signIn('KEYHAN', 'supersecret1');
      expect(s.role, Role.owner);
      expect(() => auth.signIn('keyhan', 'nope-nope-nope'), throwsA(isA<AuthError>()));
      expect(() => auth.signIn('nobody', 'supersecret1'), throwsA(isA<AuthError>()));
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
      await db.seedDefaults('Keyhan Azarjoo');
      await db.seedDefaults('Keyhan Azarjoo');
      expect(await db.count('agents'), 2);
      final ava = (await db.all('agents', orderBy: 'id')).first;
      expect(ava['name'], 'Ava');
      expect(ava['greeting'] as String, contains('Keyhan'));
      expect(await db.count('skills'), greaterThan(3));
    });
    test('settings round-trip', () async {
      await db.setSetting('k', 'v1');
      await db.setSetting('k', 'v2');
      expect(await db.setting('k'), 'v2');
      expect(await db.setting('missing'), isNull);
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
    final models = await o.installed();
    if (models.isEmpty) {
      markTestSkipped('No models installed');
      return;
    }
    final out = await o.chat(models.first.name, [ChatMessage('user', 'Reply with the single word: ready')]).join();
    expect(out.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
