import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:localailine_model/users.dart';
import 'package:localailine_model/mcp.dart';
import 'package:localailine_ui/app_model.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'connectors_section.dart';
import 'knowledge_page.dart' show addSkillFromDocument;
import 'main_pages.dart' show Rows;
import '../extras.dart';

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

Widget _delete(AppModel s, String table, int id, String what) => Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
      await s.db.delete(table, id);
      await s.log('Removed $what');
      s.refresh();
    });

// ============================ Agents ============================

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
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
    final s = context.watch<AppModel>();
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
    final s = context.watch<AppModel>();
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

const scopes = {'all': 'Phone calls too (callers and calls Ava makes)', 'contacts': 'Calls with my contacts', 'me': 'Only me (chat and Talk)'};

// ============================ Tools (MCP) ============================

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final open = <int>{};

  @override
  void initState() {
    super.initState();
    // Reconnect quietly; never pop a browser without the user asking.
    final s = context.read<AppModel>();
    s.mcp.servers().then((list) {
      for (final srv in list) {
        if (srv.enabled && s.mcp.status[srv.id] == null && srv.row['status'] != 'needs_sign_in') s.mcp.connect(srv.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Tools & connectors',
          description: 'Connect your apps (email, calendar, work tools) or any MCP server, so Ava can look things up and act for you. Anything that changes data asks you first.',
          actions: [Btn('Add MCP server', icon: Icons.add, kind: BtnKind.primary, onPressed: () => showMcpDialog(context))]),
      FutureBuilder(
        future: s.mcp.servers(),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (snap.hasData && list.isEmpty) {
            return Panel(
                child: EmptyState(
              icon: Icons.power_outlined,
              title: 'No tools connected',
              body: 'Add an MCP server by URL or local command. If it needs a login, you’ll sign in in your browser.',
              action: Btn('Add MCP server', icon: Icons.add, kind: BtnKind.primary, onPressed: () => showMcpDialog(context)),
            ));
          }
          return Column(children: [for (final srv in list) ...[_server(context, s, srv), const SizedBox(height: 12)]]);
        },
      ),
      const SizedBox(height: 18),
      const ConnectorsSection(),
    ]);
  }

  Widget _server(BuildContext context, AppModel s, McpServer srv) {
    final st = s.mcp.statusOf(srv);
    final tools = srv.tools;
    final err = s.mcp.errorOf(srv);
    final (label, tone, lamp) = switch (st) {
      McpStatus.connected => ('Connected · ${tools.length} tool${tools.length == 1 ? '' : 's'}', Tone.green, LampState.on),
      McpStatus.connecting => ('Connecting…', Tone.amber, LampState.ring),
      McpStatus.needsSignIn => ('Needs sign-in', Tone.amber, LampState.off),
      McpStatus.error => ('Can’t connect', Tone.red, LampState.err),
      McpStatus.unknown => (tools.isEmpty ? 'Not connected' : '${tools.length} tools · not connected yet', Tone.neutral, LampState.off),
    };
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(children: [
            const LogoBox(child: Icon(Icons.power_outlined)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(srv.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Pill(label, tone: tone, lamp: lamp),
                ]),
                const SizedBox(height: 2),
                Muted('${srv.target} · ${switch (srv.authMode) { McpAuthMode.auto => 'signs in when asked', McpAuthMode.token => 'API key / token', McpAuthMode.none => 'no sign-in' }} · ${scopes[srv.scope] ?? ''}',
                    mono: true, size: 11.5),
                if (st == McpStatus.error && err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err, style: const TextStyle(color: LL.red, fontSize: 12.5))),
                if (st == McpStatus.needsSignIn)
                  const Padding(padding: EdgeInsets.only(top: 4), child: Muted('This server asks you to log in. Your browser will open its sign-in page.')),
              ]),
            ),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (st == McpStatus.needsSignIn)
                Btn('Sign in', icon: Icons.login, kind: BtnKind.primary, small: true, onPressed: () => s.mcp.connect(srv.id, interactive: true))
              else if (st != McpStatus.connecting)
                Btn(st == McpStatus.connected ? 'Refresh' : 'Connect', small: true, onPressed: () => s.mcp.connect(srv.id, interactive: true)),
              if (srv.authMode == McpAuthMode.auto && srv.secret['accessToken'] != null)
                Btn('Sign out', small: true, kind: BtnKind.ghost, onPressed: () => s.mcp.signOut(srv.id)),
              Btn('Edit', small: true, kind: BtnKind.ghost, onPressed: () => showMcpDialog(context, existing: srv)),
              Switch(value: srv.enabled, onChanged: (v) async {
                await s.db.update('mcp_servers', srv.id, {'enabled': v ? 1 : 0});
                if (!v) await s.mcp.disconnect(srv.id);
                s.refresh();
              }),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await s.mcp.disconnect(srv.id);
                  await s.db.delete('mcp_servers', srv.id);
                  await s.log('Removed MCP server ${srv.name}');
                  s.refresh();
                },
              ),
            ]),
          ]),
        ),
        if (tools.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => open.contains(srv.id) ? open.remove(srv.id) : open.add(srv.id)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.c.line))),
              child: Row(children: [
                Icon(open.contains(srv.id) ? Icons.expand_less : Icons.expand_more, size: 18),
                const SizedBox(width: 6),
                Text('${open.contains(srv.id) ? 'Hide' : 'Show'} ${tools.length} tools', style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Muted('${tools.where((t) => t.readOnly).length} read-only · ${tools.where((t) => !t.readOnly).length} ask first'),
              ]),
            ),
          ),
          if (open.contains(srv.id))
            for (final t in tools)
              Tile(
                last: t == tools.last,
                title: Text(t.title ?? t.name, style: const TextStyle(fontFamily: LL.mono, fontSize: 12.5, fontWeight: FontWeight.w500)),
                subtitle: Muted(t.description, size: 12.5),
                trailing: Pill(t.readOnly ? 'Read only' : 'Asks first', tone: t.readOnly ? Tone.green : Tone.amber),
              ),
        ],
      ]),
    );
  }
}

Future<void> showMcpDialog(BuildContext context, {McpServer? existing}) =>
    showDialog(context: context, builder: (_) => _McpDialog(existing: existing));

class _McpDialog extends StatefulWidget {
  const _McpDialog({this.existing});
  final McpServer? existing;
  @override
  State<_McpDialog> createState() => _McpDialogState();
}

class _McpDialogState extends State<_McpDialog> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final target = TextEditingController(text: widget.existing?.target ?? '');
  late final header = TextEditingController(text: (widget.existing?.secret['header'] as String?) ?? 'Authorization');
  late final value = TextEditingController(text: (widget.existing?.secret['value'] as String?) ?? '');
  late final env = TextEditingController(
      text: ((widget.existing?.secret['env'] as Map?) ?? {}).entries.map((e) => '${e.key}=${e.value}').join('\n'));
  late String kind = widget.existing?.kind ?? 'http';
  late McpAuthMode auth = widget.existing?.authMode ?? McpAuthMode.auto;
  late String scope = widget.existing?.scope ?? 'me';
  String? error;

  Future<void> _save() async {
    final s = context.read<AppModel>();
    if (name.text.trim().isEmpty || target.text.trim().isEmpty) return setState(() => error = 'Add a name and a URL or command.');
    if (kind == 'http' && !RegExp(r'^https?://').hasMatch(target.text.trim())) return setState(() => error = 'The URL must start with https://');
    final secret = kind == 'stdio'
        ? {
            'env': {
              for (final l in env.text.split('\n').where((l) => l.contains('=')))
                l.substring(0, l.indexOf('=')).trim(): l.substring(l.indexOf('=') + 1).trim()
            }
          }
        : auth == McpAuthMode.token
            ? {'header': header.text.trim(), 'value': value.text.trim()}
            : auth == McpAuthMode.auto && widget.existing?.authMode == McpAuthMode.auto && widget.existing?.target == target.text.trim()
                ? widget.existing!.secret // keep the existing login
                : <String, dynamic>{};
    final row = {
      'name': name.text.trim(),
      'kind': kind,
      'target': target.text.trim(),
      'scope': scope,
      'auth_mode': kind == 'stdio' ? 'none' : auth.name,
      'secret': jsonEncode(secret),
      'enabled': 1,
    };
    int id;
    if (widget.existing != null) {
      id = widget.existing!.id;
      await s.db.update('mcp_servers', id, row);
    } else {
      id = await s.db.insert('mcp_servers', row);
    }
    await s.log('${widget.existing == null ? 'Added' : 'Updated'} MCP server ${name.text.trim()}');
    if (mounted) Navigator.pop(context);
    s.refresh();
    // Connect now; if the server wants a login, the browser opens.
    await s.mcp.connect(id, interactive: true);
  }

  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.existing == null ? 'Add MCP server' : 'Edit MCP server', style: displayStyle(context, 22)),
              const SizedBox(height: 16),
              Field(label: 'Name', child: TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Weighing system'))),
              const SizedBox(height: 12),
              Segmented(value: kind, options: const {'http': 'URL', 'stdio': 'Local command'}, onChanged: (v) => setState(() => kind = v)),
              const SizedBox(height: 12),
              Field(
                label: kind == 'http' ? 'Server URL' : 'Command',
                hint: kind == 'http' ? null : 'Runs on this computer, e.g. npx -y @modelcontextprotocol/server-filesystem ~/Documents',
                child: TextField(controller: target, decoration: InputDecoration(hintText: kind == 'http' ? 'https://example.com/mcp' : 'npx -y …')),
              ),
              const SizedBox(height: 14),
              if (kind == 'http') ...[
                Field(
                  label: 'Sign-in',
                  child: Dropdown(value: auth, items: const {
                    McpAuthMode.auto: 'Automatic — log in in my browser when the server asks',
                    McpAuthMode.token: 'API key or token',
                    McpAuthMode.none: 'None',
                  }, onChanged: (v) => setState(() => auth = v)),
                ),
                if (auth == McpAuthMode.token) ...[
                  const SizedBox(height: 12),
                  Grid(cols: 2, children: [
                    Field(label: 'Header', child: TextField(controller: header)),
                    Field(
                      label: 'Value',
                      hint: header.text.trim().toLowerCase() == 'authorization' ? 'Usually “Bearer ” followed by the token' : null,
                      child: TextField(controller: value, obscureText: true, decoration: const InputDecoration(hintText: 'Bearer abc123…')),
                    ),
                  ]),
                ],
              ] else
                Field(
                  label: 'Environment variables (optional)',
                  hint: 'One per line, e.g. API_KEY=abc123',
                  child: TextField(controller: env, maxLines: 3),
                ),
              const SizedBox(height: 12),
              Field(label: 'Who can use it', child: Dropdown(value: scope, items: scopes, onChanged: (v) => setState(() => scope = v))),
              const SizedBox(height: 6),
              const Muted('“Only me” means Ava uses it when you chat or give instructions, never for callers.'),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: LL.red))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Btn('Cancel', onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Btn(widget.existing == null ? 'Add and connect' : 'Save and connect', kind: BtnKind.primary, onPressed: _save),
              ]),
            ]),
          ),
        ),
      );
}

// ============================ Skills ============================

class SkillsPage extends StatelessWidget {
  const SkillsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Skills',
          description: 'Ready-made behaviours you switch on. Add one from a document (for example a restaurant guide) and Ava follows it.',
          actions: [Btn('Add skill from a document', icon: Icons.upload_file, kind: BtnKind.primary, onPressed: () => addSkillFromDocument(context))]),
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
                  if ((k['instructions'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Pill(k['source_id'] == null ? 'Instructions' : 'From a document · searchable', tone: Tone.blue),
                    const SizedBox(height: 6),
                    Row(children: [
                      Btn('View', small: true, onPressed: () => showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                                title: Text(k['name'] as String),
                                content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(k['instructions'] as String))),
                                actions: [Btn('Close', onPressed: () => Navigator.pop(c))],
                              ))),
                      const SizedBox(width: 6),
                      Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
                        if (k['source_id'] != null) await s.knowledge.removeSource(k['source_id'] as int);
                        await s.db.delete('skills', k['id'] as int);
                        s.refresh();
                      }),
                    ]),
                  ],
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ Users & access ============================

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    final canManage = s.user?.can(Perm.manageUsers) ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Users & access', description: 'Everyone who can sign in to ${appNameOf(context)} on this computer, and what they can do.', actions: [
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
