
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

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => message;
}
