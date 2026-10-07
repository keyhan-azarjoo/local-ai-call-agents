import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../services/ollama.dart';
import '../../services/system.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'devices_section.dart';
import 'engine_pages.dart';
import 'knowledge_page.dart';
import 'live_calls.dart';
import 'test_runs_section.dart';

/// Loads rows from the database and rebuilds whenever AppState notifies.
class Rows extends StatelessWidget {
  const Rows(this.table, {super.key, required this.builder, this.where, this.args, this.orderBy});
  final String table;
  final String? where, orderBy;
  final List<Object?>? args;
  final Widget Function(BuildContext, List<Map<String, Object?>>) builder;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FutureBuilder(
      future: s.db.all(table, where: where, args: args, orderBy: orderBy),
      builder: (context, snap) => snap.hasData ? builder(context, snap.data!) : const SizedBox(height: 60),
    );
  }
}

Tone outcomeTone(String o) => switch (o) {
      'Blocked' => Tone.red,
      'Screened' => Tone.amber,
      'Test' => Tone.blue,
      _ => Tone.green,
    };

// ============================ Home ============================

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final first = s.user?.name.split(' ').first ?? '';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Rows('lines', builder: (context, lines) {
            final connected = lines.where((l) => l['status'] == 'connected').toList();
            final title = !s.llmReady
                ? 'Let’s finish setting up, $first.'
                : !s.answering
                    ? 'Ava is not answering calls.'
                    : lines.isEmpty
                        ? 'Ava is ready. Connect a phone line next.'
                        : connected.isEmpty
                            ? 'Ava is ready. Your line connects in the next release.'
                            : 'Ava is answering your calls.';
            return Panel(
              padding: const EdgeInsets.all(28),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Lamp(s.llmReady && s.answering ? (connected.isEmpty ? LampState.ring : LampState.on) : LampState.off),
                      const SizedBox(width: 8),
                      Eyebrow(lines.isEmpty ? 'No phone line yet' : '${lines.length} phone line${lines.length == 1 ? '' : 's'} · ${connected.length} connected'),
                    ]),
                    const SizedBox(height: 10),
                    Text(title, style: displayStyle(context, 30)),
                    const SizedBox(height: 6),
                    Muted(!s.llmReady ? 'Ava needs an AI before she can talk.' : s.usingCloud ? 'Thinking with ${s.llmLabel}' : 'Everything runs on this computer · thinking with ${s.llmModel}', size: 14),
                    if (lines.isEmpty && s.llmReady) ...[
                      const SizedBox(height: 14),
                      Btn('Connect a phone line', icon: Icons.add, kind: BtnKind.primary, onPressed: () => s.go(PageId.lines)),
                    ],
                  ]),
                ),
                Column(children: [
                  const Muted('Answering'),
                  Switch(value: s.answering, onChanged: s.setAnswering),
                ]),
              ]),
            );
          }),
          if (!s.llmReady) ...[const SizedBox(height: 16), const EngineSetupPanel()],
          const SizedBox(height: 16),
          Grid(cols: 3, children: [
            _Action(Icons.phone_forwarded_outlined, 'Make a call', 'Tell Ava who to call and why.', () => s.go(PageId.outbound)),
            _Action(Icons.mic_none_rounded, 'Talk to Ava', 'Try her as a caller, or give her instructions.', () => s.go(PageId.talk)),
            _Action(Icons.smart_toy_outlined, 'Change what Ava says', 'Greeting, instructions, voice.', () => s.editAgent(null)),
          ]),
          const LiveCallsPanel(),
          const TestRunBanner(),
          const SizedBox(height: 16),
          Rows('calls', builder: (context, calls) => Section(
                title: 'Latest calls',
                trailing: Btn('See all', small: true, onPressed: () => s.go(PageId.calls)),
                children: [
                  if (calls.isEmpty)
                    EmptyState(
                      icon: Icons.call_outlined,
                      title: 'No calls yet',
                      body: 'Calls Ava answers or makes appear here. Try a test call from this computer.',
                      action: Btn('Talk to Ava', kind: BtnKind.amber, icon: Icons.mic_none_rounded, onPressed: () => s.go(PageId.talk)),
                    ),
                  for (final c in calls.take(5)) callTile(context, c, last: c == calls.take(5).last),
                ],
              )),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.title, this.body, this.onTap);
  final IconData icon;
  final String title, body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LL.r),
        child: Panel(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LogoBox(accent: true, child: Icon(icon)),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontFamily: LL.display, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Muted(body),
          ]),
        ),
      );
}

Widget callTile(BuildContext context, Map<String, Object?> c, {bool last = false}) => Tile(
      last: last,
      onTap: () => showCall(context, c),
      leading: LogoBox(child: Icon(c['direction'] == 'outgoing' ? Icons.phone_forwarded_outlined : c['direction'] == 'test' ? Icons.mic_none_rounded : Icons.call_received)),
      title: Text((c['name'] as String?)?.isNotEmpty == true ? c['name'] as String : (c['number'] as String? ?? 'Unknown')),
      subtitle: Muted((c['summary'] as String?) ?? ''),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Pill(c['outcome'] as String, tone: outcomeTone(c['outcome'] as String)),
        const SizedBox(height: 4),
        Muted(ago(c['started_at'] as int), mono: true, size: 11.5),
      ]),
    );

void showCall(BuildContext context, Map<String, Object?> c) {
  final turns = (jsonDecode((c['transcript'] as String?) ?? '[]') as List).cast<Map>();
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((c['name'] as String?) ?? 'Call', style: displayStyle(ctx, 22)),
            Muted('${c['line'] ?? ''} · ${ago(c['started_at'] as int)}', mono: true),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(children: [
                for (final t in turns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 76,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Eyebrow(t['who'] == 'ai' ? 'AI' : 'Caller'),
                          if (t['at'] != null) Muted('${t['at']}', mono: true, size: 10.5),
                          if (t['ms'] != null) Muted('${((t['ms'] as num) / 1000).toStringAsFixed(1)} s', mono: true, size: 10.5),
                        ]),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: t['who'] == 'ai' ? ctx.c.amberSoft : ctx.c.canvas, borderRadius: BorderRadius.circular(LL.r)),
                          child: SelectableText('${t['text']}'),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                if ((c['recording'] as String?)?.isNotEmpty == true && File(c['recording'] as String).existsSync())
                  Btn('Play recording', onPressed: () => Process.run('open', [c['recording'] as String])),
                Btn('Delete', kind: BtnKind.danger, onPressed: () async {
                  final s = ctx.read<AppState>();
                  await s.db.delete('calls', c['id'] as int);
                  await s.log('Deleted a call record');
                  s.refresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
                Btn('Close', kind: BtnKind.primary, onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ============================ Calls ============================

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  late String filter = context.read<AppState>().callsFilter;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead('Calls', description: 'Every call is kept on this computer only.'),
        const LiveCallsPanel(always: true),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final s = context.watch<AppState>();
          return Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchRow('Record calls', value: s.recordCalls, onChanged: s.setRecordCalls),
              const Muted('Both sides of each phone call, kept on this computer. Callers hear “This call may be recorded.” at the start.', size: 12.5),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('Calls at the same time', style: TextStyle(fontSize: 13.5))),
                SizedBox(
                  width: 120,
                  child: Dropdown<int>(
                    value: s.lines,
                    items: {for (var n = 1; n <= AppState.maxLines; n++) n: '$n'},
                    onChanged: s.setLines,
                  ),
                ),
              ]),
              const Muted('Each call is heard, answered and spoken at the same time as the others, not one after another. '
                  'Set it to what this computer can take; more calls are still answered, just more slowly.', size: 12.5),
            ]),
          );
        }),
        const RequestsSection(),
        const SizedBox(height: 16),
        Segmented(
          value: filter,
          options: const {'all': 'All', 'incoming': 'Incoming', 'outgoing': 'Made by AI', 'test': 'Tests'},
          onChanged: (v) => setState(() => filter = context.read<AppState>().callsFilter = v),
        ),
        const SizedBox(height: 14),
        if (filter == 'test') ...[const TestRunsSection(), const SizedBox(height: 14)],
        Rows('calls',
            where: filter == 'all' ? null : 'direction = ?',
            args: filter == 'all' ? null : [filter],
            builder: (context, calls) => Section(title: '${calls.length} call${calls.length == 1 ? '' : 's'}', children: [
                  if (calls.isEmpty)
                    const EmptyState(icon: Icons.call_outlined, title: 'Nothing here yet', body: 'Calls appear as soon as Ava answers or makes one.'),
                  for (final c in calls) callTile(context, c, last: c == calls.last),
                ])),
      ]);
}

// ============================ Make a call ============================

class OutboundPage extends StatefulWidget {
  const OutboundPage({super.key});
  @override
  State<OutboundPage> createState() => _OutboundPageState();
}

class _OutboundPageState extends State<OutboundPage> {
  final ask = TextEditingController();
  final who = TextEditingController();
  final number = TextEditingController();
  final goal = TextEditingController();
  final findOut = TextEditingController();
  final share = TextEditingController();
  String retry = '2x30';
  String when = 'now';
  int? editingId;
  bool drafting = false;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  /// A draft created from Talk lands here for review.
  Future<void> _loadDraft() async {
    final s = context.read<AppState>();
    final d = await s.db.all('call_tasks', where: "status = 'draft'", orderBy: 'id DESC');
    if (d.isNotEmpty && mounted) {
      setState(() {
        editingId = d.first['id'] as int;
        who.text = (d.first['to_name'] as String?) ?? '';
        number.text = (d.first['number'] as String?) ?? '';
        goal.text = (d.first['goal'] as String?) ?? '';
      });
    }
  }

  Future<void> _draftFromAsk() async {
    final s = context.read<AppState>();
    if (ask.text.trim().isEmpty) return;
    if (!s.llmReady) return s.toast('Set up the AI first (Settings).');
    setState(() => drafting = true);
    try {
      final buf = StringBuffer();
      await for (final p in s.chat([
        ChatMessage('system',
            'Extract a phone call task from the user request. Reply with JSON only: {"to": "<who to call>", "number": "<phone number if given, else empty>", "goal": "<what to achieve, written as an instruction to the caller agent>"}'),
        ChatMessage('user', ask.text),
      ])) {
        buf.write(p);
      }
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(buf.toString());
      final j = jsonDecode(m!.group(0)!) as Map<String, dynamic>;
      setState(() {
        who.text = '${j['to'] ?? ''}';
        number.text = '${j['number'] ?? ''}';
        goal.text = '${j['goal'] ?? ask.text}';
      });
    } catch (_) {
      setState(() => goal.text = ask.text);
      s.toast('Filled in the goal. Add who to call and their number.');
    } finally {
      if (mounted) setState(() => drafting = false);
    }
  }

  Future<int?> _save(String status) async {
    final s = context.read<AppState>();
    if (number.text.trim().isEmpty || goal.text.trim().isEmpty) {
      s.toast('Add a phone number and a goal.');
      return null;
    }
    final row = {
      'to_name': who.text.trim(),
      'number': number.text.trim(),
      'goal': [
        goal.text.trim(),
        if (findOut.text.trim().isNotEmpty) 'Find out: ${findOut.text.trim()}',
        if (share.text.trim().isNotEmpty) 'Allowed to share: ${share.text.trim()}',
      ].join('\n'),
      'status': status,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    final int id;
    if (editingId != null) {
      id = editingId!;
      await s.db.update('call_tasks', id, row);
    } else {
      id = await s.db.insert('call_tasks', row);
    }
    await s.log('${status == 'queued' ? 'Queued' : 'Saved'} a call to ${who.text.isEmpty ? number.text : who.text}');
    setState(() {
      editingId = null;
      for (final c in [ask, who, number, goal, findOut, share]) {
        c.clear();
      }
    });
    s.refresh();
    return id;
  }

  Future<void> _start() async {
    final s = context.read<AppState>();
    // Calls go out on a Twilio line (other line types can't dial out yet).
    final lines = await s.db.count('lines', where: "provider = 'twilio'");
    if (lines == 0 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Connect a phone line to call', style: displayStyle(c, 20)),
          content: const Text('Ava calls from your own number. Add a Twilio phone line first. Your call will wait in the queue until then.'),
          actions: [
            Btn('Keep in queue', onPressed: () => Navigator.pop(c, false)),
            Btn('Connect a line', kind: BtnKind.primary, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      );
      await _save('queued');
      if (go == true) s.go(PageId.lines);
      return;
    }
    final id = await _save('queued');
    if (id == null) return;
    s.toast('Calling…');
    await s.placeCall(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead('Make a call',
          description: 'Tell Ava who to call and what to achieve. She calls from your number, says she is your AI assistant, and reports back.'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Just ask'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ask,
                onSubmitted: (_) => _draftFromAsk(),
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(hintText: 'e.g. Call Riverside Dental on 020 7946 0011 and move my check-up to next week'),
              ),
            ),
            const SizedBox(width: 8),
            Btn(drafting ? 'Drafting…' : 'Draft call', icon: Icons.phone_forwarded_outlined, kind: BtnKind.primary, large: true, onPressed: drafting ? null : _draftFromAsk),
          ]),
          const SizedBox(height: 8),
          const Muted('Or fill in the details. Nothing is dialled until you press Start call.'),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Call details', style: displayStyle(context, 17)),
            const Spacer(),
            if (editingId != null) const Pill('Draft', tone: Tone.amber),
          ]),
          const SizedBox(height: 16),
          Grid(cols: 2, children: [
            Field(label: 'Who to call', child: TextField(controller: who, decoration: const InputDecoration(hintText: 'Name or business'))),
            Field(label: 'Phone number', child: TextField(controller: number, decoration: const InputDecoration(hintText: '+44 20 7946 0011'))),
          ]),
          const SizedBox(height: 14),
          Field(label: 'Goal', child: TextField(controller: goal, maxLines: 3, decoration: const InputDecoration(hintText: 'What should Ava achieve on this call?'))),
          if (s.advanced) ...[
            const SizedBox(height: 14),
            Grid(cols: 2, children: [
              Field(label: 'Must find out', hint: 'Comma separated', child: TextField(controller: findOut, decoration: const InputDecoration(hintText: 'New time, any fee'))),
              Field(label: 'Allowed to share', hint: 'Anything not listed stays private.', child: TextField(controller: share, decoration: const InputDecoration(hintText: 'My full name, date of birth'))),
              Field(label: 'If no answer', child: Dropdown(value: retry, items: const {'2x30': 'Retry 2× every 30 min', 'vm': 'Leave a voicemail', 'none': 'Give up'}, onChanged: (v) => setState(() => retry = v))),
              Field(label: 'When', child: Dropdown(value: when, items: const {'now': 'Now', 'hours': 'Next business hours'}, onChanged: (v) => setState(() => when = v))),
            ]),
          ] else ...[
            const SizedBox(height: 8),
            Btn('More options', small: true, kind: BtnKind.ghost, onPressed: () => s.setAdvanced(true)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.shield_outlined, size: 15),
            const SizedBox(width: 6),
            const Expanded(child: Muted('Ava opens with “Hi, I’m an AI assistant calling on behalf of …”.')),
            Btn('Save for later', onPressed: () => _save('saved')),
            const SizedBox(width: 8),
            Btn('Start call', icon: Icons.phone_forwarded_outlined, kind: BtnKind.amber, onPressed: _start),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Rows('call_tasks', where: "status != 'draft'", builder: (context, tasks) => Section(title: 'Call queue', children: [
            if (tasks.isEmpty) const EmptyState(icon: Icons.schedule, title: 'No calls waiting', body: 'Calls you start or save appear here.'),
            for (final t in tasks)
              Tile(
                last: t == tasks.last,
                leading: const LogoBox(child: Icon(Icons.phone_forwarded_outlined)),
                title: Text((t['to_name'] as String?)?.isNotEmpty == true ? t['to_name'] as String : t['number'] as String),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Muted('${t['number']} · ${(t['goal'] as String).split('\n').first}'),
                  if ('${t['result'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${t['result']}', style: TextStyle(fontSize: 13, color: t['status'] == 'failed' ? LL.red : null)),
                    ),
                ]),
                trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(
                    switch (t['status']) {
                      'calling' => 'Calling…',
                      'done' => 'Done',
                      'no_answer' => 'No answer',
                      'failed' => 'Didn’t go through',
                      'queued' => 'Waiting',
                      _ => 'Saved',
                    },
                    tone: switch (t['status']) {
                      'calling' => Tone.amber,
                      'done' => Tone.green,
                      'failed' => Tone.red,
                      _ => Tone.neutral,
                    },
                  ),
                  if (t['status'] != 'calling')
                    Btn(t['status'] == 'done' ? 'Call again' : (t['status'] == 'failed' || t['status'] == 'no_answer' ? 'Try again' : 'Call now'),
                        small: true, icon: Icons.call, onPressed: () => s.placeCall(t['id'] as int)),
                  Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
                    await s.db.delete('call_tasks', t['id'] as int);
                    s.refresh();
                  }),
                ]),
              ),
          ])),
    ]);
  }
}

// ============================ My assistant ============================

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  Map<String, Object?>? agent;
  final name = TextEditingController();
  final greeting = TextEditingController();
  final instructions = TextEditingController();
  String language = 'English';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final rows = s.editAgentId == null
        ? await s.db.all('agents', where: "handles = 'incoming'", orderBy: 'id')
        : await s.db.all('agents', where: 'id = ?', args: [s.editAgentId]);
    if (rows.isEmpty || !mounted) return;
    setState(() {
      agent = rows.first;
      name.text = agent!['name'] as String;
      greeting.text = agent!['greeting'] as String;
      instructions.text = agent!['instructions'] as String;
      language = agent!['language'] as String;
    });
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    await s.db.update('agents', agent!['id'] as int, {
      'name': name.text.trim().isEmpty ? 'Ava' : name.text.trim(),
      'greeting': greeting.text.trim(),
      'instructions': instructions.text.trim(),
      'language': language,
    });
    await s.log('Updated assistant ${name.text}');
    s.toast('Saved. Ava will use this on the next call.');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (agent == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('${agent!['name']} · ${agent!['role']}', description: 'How this assistant sounds, what it says first, and how it behaves on calls.', actions: [
        Btn('Try it', icon: Icons.mic_none_rounded, kind: BtnKind.amber, onPressed: () async {
          await _save();
          s.go(PageId.talk);
        }),
        Btn('Save changes', kind: BtnKind.primary, onPressed: _save),
      ]),
      Grid(cols: 2, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(label: 'Name', child: TextField(controller: name)),
            const SizedBox(height: 14),
            Field(label: 'First thing callers hear', child: TextField(controller: greeting, maxLines: 2)),
            const SizedBox(height: 14),
            Field(label: 'Instructions', hint: 'Write it like you’d brief a person.', child: TextField(controller: instructions, maxLines: 8)),
          ]),
        ),
        Column(children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Field(
                label: 'Language',
                child: Dropdown(value: language, items: const {
                  'English': 'English',
                  'Persian (فارسی)': 'Persian (فارسی)',
                  'Spanish': 'Spanish',
                  'French': 'French',
                  'German': 'German',
                  'Arabic': 'Arabic',
                }, onChanged: (v) => setState(() => language = v)),
              ),
              const SizedBox(height: 14),
              Field(
                label: 'Voice',
                child: Dropdown(
                  value: s.ttsVoice,
                  items: {for (final v in s.catalog.tts) v.id: '${v.name}${s.speech.ttsVoicePath(v.id) == null ? ' — not downloaded' : ''}'},
                  onChanged: s.setTtsVoice,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Btn('Hear greeting', icon: Icons.volume_up_outlined, small: true,
                    onPressed: () => s.speech.speak(greeting.text, voicePath: s.speech.ttsVoicePath(s.ttsVoice))),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const KnowledgeList(compact: true),
          const SizedBox(height: 16),
          Rows('skills', orderBy: 'id', builder: (context, skills) => Section(
              title: 'What Ava can do',
              trailing: Btn('Add skill', icon: Icons.upload_file, small: true, onPressed: () => addSkillFromDocument(context)),
              children: [
                for (final k in skills)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: SwitchRow(k['name'] as String, value: k['enabled'] == 1, onChanged: (v) async {
                      await s.db.update('skills', k['id'] as int, {'enabled': v ? 1 : 0});
                      s.refresh();
                    }),
                  ),
                const SizedBox(height: 8),
              ])),
        ]),
      ]),
    ]);
  }
}

// ============================ Phone line ============================

const providers = <String, (String, List<(String, String, bool)>)>{
  // key: (label, fields[(key, label, secret)])
  'twilio': ('Twilio', [('sid', 'Account SID (starts with AC)', false), ('token', 'Auth token (or API key secret)', true), ('keySid', 'API key SID (optional, starts with SK)', false), ('number', 'Phone number (e.g. +441234567890)', false)]),
  'telnyx': ('Telnyx', [('apiKey', 'API key', true), ('sipUser', 'SIP username', false), ('sipPass', 'SIP password', true), ('number', 'Phone number', false)]),
  'sip': ('Other SIP provider', [('server', 'SIP server', false), ('sipUser', 'Username', false), ('sipPass', 'Password', true), ('number', 'Phone number', false)]),
  'fxo': ('Landline (FXO box)', [('host', 'Gateway address (e.g. 192.168.1.40)', false), ('number', 'Landline number', false)]),
};

class LinesPage extends StatelessWidget {
  const LinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Phone line', description: 'Connect a number from a provider, or a landline. Calls on any line go to Ava.', actions: [
        Btn('Add phone line', icon: Icons.add, kind: BtnKind.primary, onPressed: () => showLineDialog(context)),
      ]),
      Rows('lines', builder: (context, lines) => Section(title: 'Your lines', children: [
            if (lines.isEmpty)
              EmptyState(
                icon: Icons.dns_outlined,
                title: 'No phone line yet',
                body: 'Add Twilio, Telnyx, any SIP provider, or a landline box.',
                action: Btn('Add phone line', kind: BtnKind.primary, icon: Icons.add, onPressed: () => showLineDialog(context)),
              ),
            for (final l in lines)
              Tile(
                last: l == lines.last,
                leading: LogoBox(child: Text(providers[l['provider']]?.$1.substring(0, 2) ?? '?', style: const TextStyle(fontWeight: FontWeight.w700))),
                title: Text(l['label'] as String),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Muted('${l['number'] ?? ''} · ${providers[l['provider']]?.$1 ?? ''}', mono: true),
                  if (l['provider'] == 'twilio') _InboundSwitch(line: l),
                ]),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(l['status'] == 'verified' ? 'Account verified · call engine coming next' : 'Saved · call engine coming next',
                      tone: l['status'] == 'verified' ? Tone.blue : Tone.neutral),
                  Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
                    await s.db.delete('lines', l['id'] as int);
                    await s.log('Removed phone line ${l['label']}');
                    s.refresh();
                  }),
                ]),
              ),
          ])),
      const SizedBox(height: 16),
      const PhonesSection(),
      const SizedBox(height: 16),
      const Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What works today', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Muted('Lines are saved and Twilio/Telnyx accounts can be checked. Answering and placing real phone calls arrives with the LocalAILine phone gateway in the next milestone.'),
        ]),
      ),
    ]);
  }
}

/// "Answer calls here": calls to the Twilio number come to Ava on this computer.
class _InboundSwitch extends StatefulWidget {
  const _InboundSwitch({required this.line});
  final Map<String, Object?> line;
  @override
  State<_InboundSwitch> createState() => _InboundSwitchState();
}

class _InboundSwitchState extends State<_InboundSwitch> {
  bool busy = false;
  String? note;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final on = RegExp(r'"inbound":\s*true').hasMatch('${widget.line['config']}');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.scale(
            scale: .8,
            child: Switch(
              value: on,
              onChanged: busy
                  ? null
                  : (v) async {
                      setState(() => busy = true);
                      final r = await s.setInbound(widget.line['id'] as int, v);
                      if (mounted) {
                        setState(() {
                          busy = false;
                          note = r;
                        });
                      }
                    },
            ),
          ),
          Text(busy ? 'Setting up…' : 'Answer calls here', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        if (note != null) Muted(note!, size: 12),
        if (on) const Muted('Ava answers calls to this number while LocalAILine is open. Turn off to give the number back to its previous setup.', size: 12),
      ]),
    );
  }
}

Future<void> showLineDialog(BuildContext context) => showDialog(context: context, builder: (_) => const _LineDialog());

class _LineDialog extends StatefulWidget {
  const _LineDialog();
  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  String provider = 'twilio';
  final ctrls = <String, TextEditingController>{};
  String? check;
  bool checking = false, verified = false;
  List<String> numbers = [];

  TextEditingController _c(String k) => ctrls.putIfAbsent(k, TextEditingController.new);

  /// Checks credentials with the provider's own API. Only the provider sees them.
  Future<void> _check() async {
    setState(() {
      checking = true;
      check = null;
    });
    try {
      if (provider == 'twilio') {
        final problem = _twilioProblem();
        if (problem != null) {
          check = problem;
          return;
        }
        final sid = _c('sid').text.trim(), token = _c('token').text.trim(), keySid = _c('keySid').text.trim();
        // Auth token: Account SID + token. API key: key SID + key secret (account in the URL).
        final user = keySid.isNotEmpty ? keySid : sid;
        final r = await http.get(Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$sid/IncomingPhoneNumbers.json?PageSize=100'),
            headers: {'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$token'))}'});
        if (r.statusCode == 200) {
          numbers = ((jsonDecode(r.body) as Map)['incoming_phone_numbers'] as List).map((n) => n['phone_number'] as String).toList();
          verified = true;
          if (numbers.isNotEmpty && _c('number').text.isEmpty) _c('number').text = numbers.first;
          check = numbers.isEmpty
              ? 'Account verified, but it has no phone numbers yet. Buy one in the Twilio console (Phone Numbers → Buy a number), then check again.'
              : 'Account verified. Pick your number below.';
        } else {
          String? detail;
          try {
            detail = (jsonDecode(r.body) as Map)['message'] as String?;
          } catch (_) {}
          check = switch (r.statusCode) {
            401 => 'Twilio didn’t accept these details${detail == null ? '' : ' ($detail)'}. Copy the Account SID and Auth token again from the Twilio console home page (click “Show” on the token).',
            404 => 'Twilio has no account with that Account SID. It starts with AC and is on the Twilio console home page.',
            _ => 'Twilio said ${r.statusCode}${detail == null ? '' : ': $detail'}.',
          };
        }
      } else if (provider == 'telnyx') {
        final r = await http.get(Uri.parse('https://api.telnyx.com/v2/phone_numbers?page[size]=20'),
            headers: {'Authorization': 'Bearer ${_c('apiKey').text.trim()}'});
        if (r.statusCode == 200) {
          final nums = ((jsonDecode(r.body) as Map)['data'] as List).map((n) => n['phone_number'] as String).toList();
          verified = true;
          if (nums.isNotEmpty && _c('number').text.isEmpty) _c('number').text = nums.first;
          check = 'Account verified. Numbers: ${nums.isEmpty ? 'none yet' : nums.join(', ')}';
        } else {
          check = 'Telnyx said ${r.statusCode}: check the API key.';
        }
      }
    } catch (e) {
      check = 'Could not reach the provider: $e';
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  /// What's wrong with the Twilio details, if anything (said in the dialog, not behind it).
  String? _twilioProblem() {
    final sid = _c('sid').text.trim(), token = _c('token').text.trim(), keySid = _c('keySid').text.trim();
    if (sid.startsWith('SK')) return 'That’s an API key SID. Put it in “API key SID”, and put your Account SID (starts with AC) in the first box.';
    if (!RegExp(r'^AC[0-9a-fA-F]{32}$').hasMatch(sid)) return 'The Account SID starts with AC and has 34 characters. Copy it from the Twilio console home page.';
    if (token.isEmpty) return 'Add the Auth token (or the API key secret).';
    if (keySid.isNotEmpty && !keySid.startsWith('SK')) return 'The API key SID starts with SK. Leave it empty if you use the Auth token.';
    return null;
  }

  /// "+44 1234 567 890", "(415) 555-0100" → "+441234567890". Numbers need the country code.
  static String normalizeNumber(String n) {
    final t = n.trim();
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.startsWith('+')) return '+$digits';
    if (t.startsWith('00')) return '+${digits.substring(2)}';
    return digits;
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final (label, fields) = providers[provider]!;
    final cfg = {for (final f in fields) f.$1: _c(f.$1).text.trim()};
    String? problem;
    final number = normalizeNumber(cfg['number']!);
    if (provider == 'twilio') problem = _twilioProblem();
    if (problem == null && number.isEmpty) problem = 'Add the phone number.';
    if (problem == null && provider != 'fxo' && !number.startsWith('+')) {
      problem = 'Write the number with its country code, e.g. +44 7700 900123 (not starting with 0).';
    }
    if (problem == null && verified && numbers.isNotEmpty && !numbers.contains(number)) {
      problem = 'That number isn’t in this Twilio account. Pick one of: ${numbers.join(', ')}';
    }
    if (problem != null) return setState(() => check = problem);
    cfg['number'] = number;
    await s.db.insert('lines', {
      'provider': provider,
      'label': label,
      'number': number,
      'config': jsonEncode(cfg),
      'status': verified ? 'verified' : 'saved',
    });
    await s.log('Added phone line $label ${cfg['number']}');
    s.refresh();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fields = providers[provider]!.$2;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add phone line', style: displayStyle(context, 22)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in providers.entries)
                ChoiceChip(
                  label: Text(e.value.$1),
                  selected: provider == e.key,
                  onSelected: (_) => setState(() {
                    provider = e.key;
                    check = null;
                    verified = false;
                    numbers = [];
                  }),
                ),
            ]),
            const SizedBox(height: 16),
            for (final f in fields) ...[
              Field(label: f.$2, child: TextField(controller: _c(f.$1), obscureText: f.$3)),
              const SizedBox(height: 12),
            ],
            if (provider == 'fxo')
              const Muted('Set the FXO box to send calls to this computer on port 5060, with SIP registration off and at least 2 rings for caller ID.'),
            const Muted('Saved in the local database on this computer only.'),
            if (check != null) ...[const SizedBox(height: 10), Text(check!, style: TextStyle(color: verified ? LL.green : LL.red, fontSize: 13))],
            if (numbers.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in numbers)
                  ChoiceChip(label: Text(n), selected: _c('number').text == n, onSelected: (_) => setState(() => _c('number').text = n)),
              ]),
            ],
            const SizedBox(height: 18),
            Row(children: [
              if (provider == 'twilio' || provider == 'telnyx') Btn(checking ? 'Checking…' : 'Check account', onPressed: checking ? null : _check),
              const Spacer(),
              Btn('Cancel', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Btn('Save line', kind: BtnKind.primary, onPressed: _save),
            ]),
          ])),
        ),
      ),
    );
  }
}

// ============================ Settings ============================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead('Settings'),
      Text('AI engine', style: displayStyle(context, 17)),
      const SizedBox(height: 10),
      const EngineSetupPanel(),
      const SizedBox(height: 22),
      Grid(cols: 2, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('General', style: displayStyle(context, 16)),
            const SizedBox(height: 8),
            SwitchRow('Answer calls with AI', value: s.answering, onChanged: s.setAnswering),
            SwitchRow('Show all features', value: s.advanced, onChanged: s.setAdvanced),
            SwitchRow('Dark appearance', value: s.themeMode == ThemeMode.dark, onChanged: (_) => s.toggleTheme()),
          ]),
        ),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your data', style: displayStyle(context, 16)),
            const SizedBox(height: 10),
            KV([
              ('Database', Mono(s.db.path.split(RegExp(r'[\\/]')).last)),
              ('Signed in as', Text('${s.user?.name} (${s.user?.role.name})')),
              ('Version', const Mono('0.1.0')),
              ('License', const Text('Apache-2.0')),
            ]),
            const SizedBox(height: 10),
            Btn('Open data folder', icon: Icons.folder_open_outlined, small: true, onPressed: () async => openExternal((await Db.dataDir()).path)),
          ]),
        ),
      ]),
    ]);
  }
}

/// What callers asked for, saved by agents: messages, bookings and orders.
class RequestsSection extends StatelessWidget {
  const RequestsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Rows('requests', orderBy: 'id DESC', builder: (context, rows) {
      final open = rows.where((r) => r['status'] == 'new').toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Section(
        title: 'Messages, bookings and orders${open.isEmpty ? '' : ' · ${open.length} new'}',
        children: [
          for (final r in rows.take(30))
            Tile(
              last: r == rows.take(30).last,
              leading: LogoBox(child: Icon(switch (r['kind']) { 'booking' => Icons.event_available, 'order' => Icons.receipt_long, _ => Icons.sticky_note_2_outlined })),
              title: Text('${r['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Muted(
                  '${switch (r['kind']) { 'booking' => 'Booking', 'order' => 'Order', _ => 'Message' }} · ${r['name'] ?? 'Caller'}${'${r['phone'] ?? ''}'.isEmpty ? '' : ' · ${r['phone']}'} · taken by ${r['agent'] ?? 'Ava'} · ${ago(r['created_at'] as int)}'),
              trailing: r['status'] == 'new'
                  ? Btn('Mark done', small: true, onPressed: () async {
                      await s.db.update('requests', r['id'] as int, {'status': 'done'});
                      s.refresh();
                    })
                  : const Pill('Done', tone: Tone.green),
            ),
        ],
      );
    });
  }
}
