import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../data/db.dart';

enum Role { owner, admin, operator, viewer }

extension RoleX on Role {
  String get label => switch (this) {
        Role.owner => 'Owner',
        Role.admin => 'Admin',
        Role.operator => 'Operator',
        Role.viewer => 'Viewer',
      };

  static Role parse(String s) => Role.values.firstWhere((r) => r.name == s, orElse: () => Role.viewer);
}

/// What each role may do. Checked by the UI and (later) by the engine API.
enum Perm { viewCalls, takeOver, approve, editAssistant, manageEngine, manageUsers }

const rolePerms = <Role, Set<Perm>>{
  Role.owner: {...Perm.values},
  Role.admin: {Perm.viewCalls, Perm.takeOver, Perm.approve, Perm.editAssistant, Perm.manageEngine},
  Role.operator: {Perm.viewCalls, Perm.takeOver, Perm.approve},
  Role.viewer: {Perm.viewCalls},
};

const permLabels = <Perm, String>{
  Perm.viewCalls: 'See calls & transcripts',
  Perm.takeOver: 'Take over live calls',
  Perm.approve: 'Approve AI actions',
  Perm.editAssistant: 'Edit assistant, skills & knowledge',
  Perm.manageEngine: 'Manage models & phone lines',
  Perm.manageUsers: 'Manage users',
};

class User {
  User(this.id, this.name, this.username, this.role);
  final int id;
  final String name, username;
  final Role role;

  bool can(Perm p) => rolePerms[role]!.contains(p);
  String get initials =>
      name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

  static User fromRow(Map<String, Object?> r) =>
      User(r['id'] as int, r['name'] as String, r['username'] as String, RoleX.parse(r['role'] as String));
}

/// Argon2id password hashing (OWASP minimum: m=19 MiB, t=2, p=1).
class PasswordHasher {
  static const _m = 19456, _t = 2, _p = 1;

  static Future<String> hash(String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final h = await _derive(password, salt, _m, _t, _p);
    return 'argon2id\$$_m\$$_t\$$_p\$${base64Encode(salt)}\$${base64Encode(h)}';
  }

  static Future<bool> verify(String password, String stored) async {
    final parts = stored.split('\$');
    if (parts.length != 6 || parts[0] != 'argon2id') return false;
    final m = int.parse(parts[1]), t = int.parse(parts[2]), p = int.parse(parts[3]);
    final salt = base64Decode(parts[4]);
    final expected = base64Decode(parts[5]);
    final got = await _derive(password, salt, m, t, p);
    if (got.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < got.length; i++) {
      diff |= got[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Future<List<int>> _derive(String pw, List<int> salt, int m, int t, int p) async {
    final algo = Argon2id(memory: m, iterations: t, parallelism: p, hashLength: 32);
    final key = await algo.deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: salt);
    return key.extractBytes();
  }
}

class AuthService {
  AuthService(this.db);
  final Db db;

  Future<bool> hasOwner() async => await db.count('users') > 0;

  Future<User> createUser({
    required String name,
    required String username,
    required String password,
    required Role role,
  }) async {
    final u = username.trim().toLowerCase();
    if (u.isEmpty || !RegExp(r'^[a-z0-9._-]{2,32}$').hasMatch(u)) {
      throw AuthError('Usernames use 2–32 letters, numbers, dots, dashes or underscores.');
    }
    if (password.length < 10) throw AuthError('Use at least 10 characters for the password.');
    if ((await db.all('users', where: 'username = ?', args: [u])).isNotEmpty) {
      throw AuthError('That username is already taken.');
    }
    final id = await db.insert('users', {
      'name': name.trim().isEmpty ? u : name.trim(),
      'username': u,
      'role': role.name,
      'pw_hash': await PasswordHasher.hash(password),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return User(id, name.trim().isEmpty ? u : name.trim(), u, role);
  }

  Future<User> signIn(String username, String password) async {
    final rows = await db.all('users', where: 'username = ?', args: [username.trim().toLowerCase()]);
    // Same error for unknown user and wrong password.
    if (rows.isEmpty || !await PasswordHasher.verify(password, rows.first['pw_hash'] as String)) {
      throw AuthError('Username or password is incorrect.');
    }
    final user = User.fromRow(rows.first);
    await db.update('users', user.id, {'last_active': DateTime.now().millisecondsSinceEpoch});
    await db.audit(user.name, 'Signed in');
    return user;
  }

  Future<List<User>> users() async => (await db.all('users', orderBy: 'id')).map(User.fromRow).toList();

  Future<void> setRole(int id, Role role) => db.update('users', id, {'role': role.name});
}

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => message;
}
