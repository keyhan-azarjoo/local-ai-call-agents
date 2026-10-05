import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth.dart';
import '../../services/speech.dart';
import '../../services/system.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'main_pages.dart' show Rows;

/// A field in [formDialog]: free text, secret, or a fixed set of options.
class FormSpec {
  const FormSpec(this.key, this.label, {this.options, this.secret = false, this.lines = 1, this.initial = '', this.hint});
  final String key, label, initial;
  final Map<String, String>? options;
  final bool secret;
  final int lines;
  final String? hint;
}

Future<void> formDialog(BuildContext context, String title, List<FormSpec> fields, String action,
    Future<String?> Function(Map<String, String>) onSave) {
  final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  final picks = {for (final f in fields.where((f) => f.options != null)) f.key: f.initial.isEmpty ? f.options!.keys.first : f.initial};
  String? error;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: displayStyle(ctx, 22)),
              const SizedBox(height: 16),
              for (final f in fields) ...[
                Field(
                  label: f.label,
                  hint: f.hint,
                  child: f.options != null
                      ? Dropdown(value: picks[f.key]!, items: f.options!, onChanged: (v) => set(() => picks[f.key] = v))
                      : TextField(controller: ctrls[f.key], obscureText: f.secret, maxLines: f.secret ? 1 : f.lines),
                ),
                const SizedBox(height: 12),
              ],
              if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: LL.red))),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Btn('Cancel', onPressed: () => Navigator.pop(ctx)),
                const SizedBox(width: 8),
                Btn(action, kind: BtnKind.primary, onPressed: () async {
                  final values = {for (final e in ctrls.entries) e.key: e.value.text.trim(), ...picks};
                  final err = await onSave(values);
                  if (err != null) {
                    set(() => error = err);
                  } else if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                }),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

Widget _delete(AppState s, String table, int id, String what) => Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
      await s.db.delete(table, id);
      await s.log('Removed $what');
      s.refresh();
    });

// ============================ Agents ============================

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Agents', description: 'Each agent has its own voice, instructions and job. Ava answers; Max makes calls for you.', actions: [
        Btn('New agent', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'New agent', const [
              FormSpec('name', 'Name'),
              FormSpec('role', 'Starts from', options: {
                'Support': 'Support',
                'Order taker': 'Order taker',
                'Appointment setter': 'Appointment setter',
                'Outbound caller': 'Outbound caller',
              }),
            ], 'Create agent', (v) async {
              if (v['name']!.isEmpty) return 'Give the agent a name.';
              await s.db.insert('agents', {
                'name': v['name'],
                'role': v['role'],
                'greeting': 'Hi, this is ${v['name']}. How can I help?',
                'instructions': 'You are ${v['name']}, a ${v['role']!.toLowerCase()} on the phone. Be brief, warm and accurate.',
                'language': 'English',
                'handles': v['role'] == 'Outbound caller' ? 'outgoing' : 'handoff',
                'enabled': 1,
              });
              await s.log('Created agent ${v['name']}');
              s.refresh();
              return null;
            })),
      ]),
      Rows('agents', orderBy: 'id', builder: (context, agents) => Grid(cols: 2, children: [
            for (final a in agents)
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const LogoBox(child: Icon(Icons.smart_toy_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['name'] as String, style: displayStyle(context, 16)),
                        Muted(a['role'] as String),
                      ]),
                    ),
                    Switch(value: a['enabled'] == 1, onChanged: (v) async {
                      await s.db.update('agents', a['id'] as int, {'enabled': v ? 1 : 0});
                      s.refresh();
                    }),
                  ]),
                  const SizedBox(height: 12),
                  Text(a['instructions'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  KV([
                    ('Handles', Text(switch (a['handles']) { 'incoming' => 'Incoming calls', 'outgoing' => 'Calls you ask it to make', _ => 'Hand-offs from Ava' })),
                    ('Language', Text(a['language'] as String)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Btn('Edit', kind: BtnKind.primary, small: true, onPressed: () => s.editAgent(a['id'] as int)),
                    const Spacer(),
                    if ((a['id'] as int) > 2) _delete(s, 'agents', a['id'] as int, 'agent ${a['name']}'),
                  ]),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Automations & loops ============================

class AutomationsPage extends StatelessWidget {
  const AutomationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Automations & loops',
          description: 'Tasks your agents run on their own: on a schedule, after a call, or in a loop until a goal is met.',
          actions: [
            Btn('New automation', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'New automation', const [
                  FormSpec('name', 'Name'),
                  FormSpec('trigger', 'Starts', options: {
                    'Every day at 08:00': 'Every day at 08:00',
                    'Every weekday at 17:00': 'Every weekday at 17:00',
                    'After every call': 'After every call',
                    'After a call ends with “Message taken”': 'After a call ends with “Message taken”',
                  }),
                  FormSpec('steps', 'Steps', lines: 4, hint: 'One step per line. Start a line with “For each” or “Repeat until” for loops.'),
                ], 'Create', (v) async {
                  if (v['name']!.isEmpty || v['steps']!.isEmpty) return 'Add a name and at least one step.';
                  await s.db.insert('automations', {
                    'name': v['name'],
                    'trigger': v['trigger'],
                    'steps': jsonEncode(v['steps']!.split('\n').where((l) => l.trim().isNotEmpty).toList()),
                    'enabled': 0,
                  });
                  await s.log('Created automation ${v['name']}');
                  s.refresh();
                  return null;
                })),
          ]),
      Rows('automations', orderBy: 'id', builder: (context, autos) => Column(children: [
            for (final a in autos) ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Lamp(a['enabled'] == 1 ? LampState.on : LampState.off),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a['name'] as String, style: displayStyle(context, 16))),
                    Switch(value: a['enabled'] == 1, onChanged: (v) async {
                      await s.db.update('automations', a['id'] as int, {'enabled': v ? 1 : 0});
                      await s.log('${v ? 'Turned on' : 'Turned off'} automation ${a['name']}');
                      s.refresh();
                    }),
                    _delete(s, 'automations', a['id'] as int, 'automation ${a['name']}'),
                  ]),
                  const SizedBox(height: 10),
                  _step('Starts', a['trigger'] as String, Tone.blue, 0),
                  for (final st in (jsonDecode(a['steps'] as String) as List).cast<String>())
                    _step(
                      st.startsWith('For each') || st.startsWith('Repeat') ? 'Loop' : 'Then',
                      st,
                      st.startsWith('For each') || st.startsWith('Repeat') ? Tone.amber : Tone.neutral,
                      st.startsWith('For each') || st.startsWith('Repeat') ? 0 : 1,
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const Muted('Automations run once the call engine is connected. Turning one on now saves your choice.'),
          ])),
    ]);
  }

  Widget _step(String kind, String text, Tone tone, int indent) => Padding(
        padding: EdgeInsets.only(left: indent * 24.0, top: 4, bottom: 4),
        child: Row(children: [SizedBox(width: 64, child: Pill(kind, tone: tone)), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))]),
      );
}

// ============================ Contacts ============================

const contactRules = {'ai': 'AI answers', 'vip': 'VIP · ring me first', 'message': 'Take a message', 'block': 'Block'};

class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Contacts & rules', description: 'Decide who Ava answers, who rings through to you, and who never gets through.', actions: [
        Btn('Add contact', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'Add contact', const [
              FormSpec('name', 'Name'),
              FormSpec('number', 'Phone number'),
              FormSpec('rule', 'When they call', options: contactRules),
            ], 'Add', (v) async {
              if (v['name']!.isEmpty || v['number']!.isEmpty) return 'Add a name and number.';
              await s.db.insert('contacts', v);
              await s.log('Added contact ${v['name']}');
              s.refresh();
              return null;
            })),
      ]),
      Rows('contacts', builder: (context, rows) => Section(title: 'Contacts', children: [
            if (rows.isEmpty) const EmptyState(icon: Icons.contact_phone_outlined, title: 'No contacts yet', body: 'Unknown callers are screened first, then Ava decides.'),
            for (final c in rows)
              Tile(
                last: c == rows.last,
                title: Text(c['name'] as String),
                subtitle: Muted(c['number'] as String, mono: true),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(contactRules[c['rule']] ?? '', tone: c['rule'] == 'block' ? Tone.red : c['rule'] == 'vip' ? Tone.amber : Tone.green),
                  _delete(s, 'contacts', c['id'] as int, 'contact ${c['name']}'),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Knowledge ============================

const scopes = {'all': 'All callers', 'contacts': 'Contacts only', 'me': 'Only me'};

class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Knowledge', description: 'Documents Ava can look up during calls. Indexed and searched on this computer.', actions: [
        Btn('Add document or folder', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'Add knowledge', const [
              FormSpec('name', 'Name', hint: 'e.g. Price list'),
              FormSpec('path', 'File or folder path'),
              FormSpec('scope', 'Who can hear it', options: scopes),
            ], 'Add', (v) async {
              final path = v['path']!;
              if (!File(path).existsSync() && !Directory(path).existsSync()) return 'That file or folder doesn’t exist.';
              await s.db.insert('knowledge', {...v, 'name': v['name']!.isEmpty ? path.split(RegExp(r'[\\/]')).last : v['name'], 'status': 'waiting'});
              await s.log('Added knowledge source $path');
              s.refresh();
              return null;
            })),
      ]),
      Rows('knowledge', builder: (context, rows) => Section(title: 'Sources', children: [
            if (rows.isEmpty) const EmptyState(icon: Icons.menu_book_outlined, title: 'No knowledge yet', body: 'Add FAQs, price lists or opening hours so Ava can answer questions.'),
            for (final k in rows)
              Tile(
                last: k == rows.last,
                leading: const LogoBox(child: Icon(Icons.description_outlined)),
                title: Text(k['name'] as String),
                subtitle: Muted(k['path'] as String, mono: true),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(scopes[k['scope']] ?? ''),
                  const Pill('Indexing arrives with the engine', tone: Tone.amber),
                  _delete(s, 'knowledge', k['id'] as int, 'knowledge ${k['name']}'),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Tools (MCP) ============================

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Tools (MCP)', description: 'Connect MCP servers so Ava can check calendars, look up orders or send texts. Anything that changes data asks you first.', actions: [
        Btn('Add MCP server', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'Add MCP server', const [
              FormSpec('name', 'Name'),
              FormSpec('kind', 'Type', options: {'stdio': 'Local command', 'http': 'URL'}),
              FormSpec('target', 'Command or URL', hint: 'e.g. npx -y @modelcontextprotocol/server-filesystem ~/Documents'),
              FormSpec('scope', 'Who can use it', options: scopes, initial: 'me'),
            ], 'Add', (v) async {
              if (v['name']!.isEmpty || v['target']!.isEmpty) return 'Add a name and a command or URL.';
              await s.db.insert('mcp_servers', {...v, 'enabled': 1});
              await s.log('Added MCP server ${v['name']}');
              s.refresh();
              return null;
            })),
      ]),
      Rows('mcp_servers', builder: (context, rows) => Section(title: 'Servers', children: [
            if (rows.isEmpty) const EmptyState(icon: Icons.power_outlined, title: 'No tools connected', body: 'Ava can talk without tools. Add one when you want her to act.'),
            for (final m in rows)
              Tile(
                last: m == rows.last,
                leading: const LogoBox(child: Icon(Icons.power_outlined)),
                title: Text(m['name'] as String),
                subtitle: Muted('${m['kind']} · ${m['target']}', mono: true),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(scopes[m['scope']] ?? ''),
                  Switch(value: m['enabled'] == 1, onChanged: (v) async {
                    await s.db.update('mcp_servers', m['id'] as int, {'enabled': v ? 1 : 0});
                    s.refresh();
                  }),
                  _delete(s, 'mcp_servers', m['id'] as int, 'MCP server ${m['name']}'),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Skills ============================

class SkillsPage extends StatelessWidget {
  const SkillsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead('Skills', description: 'Ready-made behaviours you switch on. Each skill is instructions plus optional tools.'),
      Rows('skills', orderBy: 'id', builder: (context, rows) => Grid(cols: 3, children: [
            for (final k in rows)
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const LogoBox(child: Icon(Icons.auto_awesome_outlined)),
                    const Spacer(),
                    Switch(value: k['enabled'] == 1, onChanged: (v) async {
                      await s.db.update('skills', k['id'] as int, {'enabled': v ? 1 : 0});
                      s.refresh();
                    }),
                  ]),
                  const SizedBox(height: 10),
                  Text(k['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Muted(k['description'] as String),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Voice server ============================

class VoiceServerPage extends StatelessWidget {
  const VoiceServerPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: Speech.which('livekit-server'),
        builder: (context, snap) {
          final bin = snap.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHead('Voice server', description: 'The built-in LiveKit server that connects phone calls, this computer and your phone to the assistant.'),
            Grid(cols: 3, children: [
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Expanded(child: Text('LiveKit server', style: TextStyle(fontWeight: FontWeight.w600))), Lamp(bin == null ? LampState.off : LampState.on)]),
                  const SizedBox(height: 4),
                  Muted(bin == null ? 'Not installed' : 'Found at $bin'),
                  const SizedBox(height: 12),
                  if (bin == null) Btn('Get LiveKit server', small: true, onPressed: () => openExternal('https://github.com/livekit/livekit/releases')),
                ]),
              ),
              const Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text('Phone gateway', style: TextStyle(fontWeight: FontWeight.w600))), Lamp(LampState.off)]),
                  SizedBox(height: 4),
                  Muted('Registers your lines and receives landline calls. Coming in the next milestone.'),
                ]),
              ),
              const Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text('Agent worker', style: TextStyle(fontWeight: FontWeight.w600))), Lamp(LampState.off)]),
                  SizedBox(height: 4),
                  Muted('Runs Ava on live calls with turn-taking and barge-in. Coming in the next milestone.'),
                ]),
              ),
            ]),
          ]);
        },
      );
}

// ============================ Paired devices ============================

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead('Paired devices', description: 'Use your phone to get ring alerts, listen in and take over calls.'),
        Panel(
          child: EmptyState(
            icon: Icons.smartphone_outlined,
            title: 'No devices paired',
            body: 'Install LocalAILine on your Android or iOS phone and pair it with this computer. Pairing arrives with the companion app.',
          ),
        ),
      ]);
}

// ============================ Users & access ============================

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final canManage = s.user?.can(Perm.manageUsers) ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Users & access', description: 'Everyone who can sign in to LocalAILine on this computer, and what they can do.', actions: [
        if (canManage)
          Btn('Add user', icon: Icons.add, kind: BtnKind.primary, onPressed: () => formDialog(context, 'Add user', [
                const FormSpec('name', 'Name'),
                const FormSpec('username', 'Username'),
                const FormSpec('password', 'Temporary password', secret: true, hint: 'At least 10 characters.'),
                FormSpec('role', 'Role', options: {for (final r in Role.values.where((r) => r != Role.owner)) r.name: r.label}, initial: 'operator'),
              ], 'Add user', (v) async {
                try {
                  await s.auth.createUser(name: v['name']!, username: v['username']!, password: v['password']!, role: RoleX.parse(v['role']!));
                  await s.log('Added user ${v['username']} as ${v['role']}');
                  s.refresh();
                  return null;
                } on AuthError catch (e) {
                  return e.message;
                }
              })),
      ]),
      FutureBuilder(
        future: s.auth.users(),
        builder: (context, snap) => Section(title: 'Users', children: [
          for (final u in snap.data ?? <User>[])
            Tile(
              leading: CircleAvatar(radius: 16, backgroundColor: LL.amber, child: Text(u.initials, style: const TextStyle(color: LL.navy, fontWeight: FontWeight.w700, fontSize: 12))),
              title: Text(u.name),
              subtitle: Muted(u.username, mono: true),
              trailing: u.role == Role.owner || !canManage
                  ? Pill(u.role.label, tone: u.role == Role.owner ? Tone.amber : Tone.blue)
                  : SizedBox(
                      width: 150,
                      child: Dropdown(
                        value: u.role.name,
                        items: {for (final r in Role.values.where((r) => r != Role.owner)) r.name: r.label},
                        onChanged: (v) async {
                          await s.auth.setRole(u.id, RoleX.parse(v));
                          await s.log('Changed ${u.username} to $v');
                          s.refresh();
                        },
                      ),
                    ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Section(title: 'What each role can do', children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(3)},
            children: [
              TableRow(children: [const SizedBox(), for (final r in Role.values) Eyebrow(r.label)]),
              for (final p in Perm.values)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(permLabels[p]!, style: const TextStyle(fontSize: 13))),
                  for (final r in Role.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: rolePerms[r]!.contains(p) ? const Icon(Icons.check, size: 16, color: LL.green) : Muted('—'),
                    ),
                ]),
            ],
          ),
        ),
      ]),
    ]);
  }
}

// ============================ Activity & logs ============================

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead('Activity & logs', description: 'Who changed what, and when.'),
        Rows('audit', builder: (context, rows) => Section(title: 'Audit trail', children: [
              if (rows.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'Nothing yet', body: 'Changes and sign-ins appear here.'),
              for (final r in rows.take(200))
                Tile(
                  last: r == rows.take(200).last,
                  title: Text(r['what'] as String, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13.5)),
                  subtitle: Muted('${r['who']} · ${ago(r['at'] as int)}', mono: true, size: 11.5),
                ),
            ])),
      ]);
}
