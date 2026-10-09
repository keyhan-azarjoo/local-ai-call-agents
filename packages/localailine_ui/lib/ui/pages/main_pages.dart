import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:localailine_model/llm.dart';
import 'package:localailine_ui/app_model.dart';
import '../../theme/tokens.dart';
import '../extras.dart';
import '../widgets.dart';
import 'knowledge_page.dart';
import 'live_calls.dart';

/// Loads rows from the database and rebuilds whenever AppModel notifies.
class Rows extends StatelessWidget {
  const Rows(this.table, {super.key, required this.builder, this.where, this.args, this.orderBy});
  final String table;
  final String? where, orderBy;
  final List<Object?>? args;
  final Widget Function(BuildContext, List<Map<String, Object?>>) builder;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
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
    final s = context.watch<AppModel>();
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
                    Muted(!s.llmReady ? 'Ava needs an AI before she can talk.' : s.usingCloud ? 'Thinking with ${s.llmLabel}' : s.usingServer ? 'Thinking with ${s.llmLabel} (your own server)' : 'Everything runs on this computer · thinking with ${s.llmLabel}', size: 14),
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
          if (!s.llmReady) ...[const SizedBox(height: 16), const Slot('engine.setup')],
          const SizedBox(height: 16),
          Grid(cols: 3, children: [
            _Action(Icons.phone_forwarded_outlined, 'Make a call', 'Tell Ava who to call and why.', () => s.go(PageId.outbound)),
            _Action(Icons.mic_none_rounded, 'Talk to Ava', 'Try her as a caller, or give her instructions.', () => s.go(PageId.talk)),
            _Action(Icons.smart_toy_outlined, 'Change what Ava says', 'Greeting, instructions, voice.', () => s.editAgent(null)),
          ]),
          const LiveCallsPanel(),
          const Slot('home.tests'),
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
                          Eyebrow(switch (t['who']) { 'ai' => 'AI', 'note' => 'Note', _ => 'Caller' }),
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
                if (context.read<AppModel>().hasRecording(c['recording'] as String?))
                  Btn('Play recording', onPressed: () => context.read<AppModel>().playRecording(c['recording'] as String)),
                Btn('Copy conversation', icon: Icons.copy, onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: [
                    for (final t in turns) '${switch (t['who']) { 'ai' => 'AI', 'note' => 'Note', _ => 'Caller' }}: ${t['text']}',
                  ].join('\n')));
                  if (ctx.mounted) ctx.read<AppModel>().toast('Conversation copied');
                }),
                Btn('Delete', kind: BtnKind.danger, onPressed: () async {
                  final s = ctx.read<AppModel>();
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
  late String filter = context.read<AppModel>().callsFilter;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead('Calls', description: 'Every call is kept on this computer only.'),
        const LiveCallsPanel(always: true),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final s = context.watch<AppModel>();
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
                    items: {for (var n = 1; n <= s.maxLines; n++) n: '$n'},
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
          onChanged: (v) => setState(() => filter = context.read<AppModel>().callsFilter = v),
        ),
        const SizedBox(height: 14),
        if (filter == 'test') ...[const Slot('calls.tests'), const SizedBox(height: 14)],
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
    final s = context.read<AppModel>();
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
    final s = context.read<AppModel>();
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
    final s = context.read<AppModel>();
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
    final s = context.read<AppModel>();
    // Calls go out on your own number, a Twilio number or a landline (Telnyx API lines can't dial out).
    final lines = await s.db.count('lines', where: "provider IN ('twilio', 'sip', 'fxo')");
    if (lines == 0 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Connect a phone line to call', style: displayStyle(c, 20)),
          content: const Text('Ava calls from your own number. Add a phone line first. Your call will wait in the queue until then.'),
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
    final s = context.watch<AppModel>();
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
    final s = context.read<AppModel>();
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
    final s = context.read<AppModel>();
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
    final s = context.watch<AppModel>();
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
                  items: s.voiceChoices(),
                  onChanged: s.setTtsVoice,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Btn('Hear greeting', icon: Icons.volume_up_outlined, small: true,
                    onPressed: () => s.previewVoice(greeting.text, s.ttsVoice)),
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
  // key: (label, fields[(key, label, secret)]). A `sip` line has its own form (_SipForm).
  'twilio': ('Twilio', [('sid', 'Account SID (starts with AC)', false), ('token', 'Auth token (or API key secret)', true), ('keySid', 'API key SID (optional, starts with SK)', false), ('number', 'Phone number (e.g. +441234567890)', false)]),
  'sip': ('My number, through my provider', []),
  'fxo': ('Landline (gateway box)', [('host', 'Gateway address (e.g. 192.168.1.40)', false), ('number', 'Landline number', false)]),
  'telnyx': ('Telnyx', [('apiKey', 'API key', true), ('sipUser', 'SIP username', false), ('sipPass', 'SIP password', true), ('number', 'Phone number', false)]),
};

Map<String, dynamic> _cfgOf(Map<String, Object?> line) {
  try {
    return (jsonDecode('${line['config'] ?? '{}'}') as Map).cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}

bool _answersHere(Map<String, Object?> l) => _cfgOf(l)['inbound'] == true;

class LinesPage extends StatelessWidget {
  const LinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Phone line', description: 'Connect your own number through your phone provider, a Twilio number, or a landline. You choose who takes the calls on each line.', actions: [
        Btn('Add phone line', icon: Icons.add, kind: BtnKind.primary, onPressed: () => showLineDialog(context)),
      ]),
      Rows('lines', builder: (context, lines) => Section(title: 'Your lines', children: [
            if (lines.isEmpty)
              EmptyState(
                icon: Icons.dns_outlined,
                title: 'No phone line yet',
                body: 'Add your own number through your phone provider, a Twilio number, or a landline box.',
                action: Btn('Add phone line', kind: BtnKind.primary, icon: Icons.add, onPressed: () => showLineDialog(context)),
              ),
            for (final l in lines)
              Tile(
                last: l == lines.last,
                leading: LogoBox(child: l['provider'] == 'sip' ? const Icon(Icons.sim_card_outlined, size: 18) : Text(providers[l['provider']]?.$1.substring(0, 2) ?? '?', style: const TextStyle(fontWeight: FontWeight.w700))),
                title: Text(l['label'] as String),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Muted('${l['number'] ?? ''} · ${providers[l['provider']]?.$1 ?? ''}', mono: true),
                  if (l['provider'] == 'sip') _SipStatusLine(status: s.sipStatus[l['id']]),
                  if (l['provider'] == 'twilio' || l['provider'] == 'fxo') _InboundSwitch(line: l),
                  if (l['provider'] == 'sip' || ((l['provider'] == 'twilio' || l['provider'] == 'fxo') && _answersHere(l))) _LineAnswerControl(line: l),
                  if (l['provider'] == 'fxo' && _answersHere(l)) _GatewaySettings(line: l),
                ]),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _LinePill(line: l, status: s.sipStatus[l['id']]),
                  Btn('', icon: Icons.edit_outlined, small: true, kind: BtnKind.ghost, onPressed: () => showLineDialog(context, line: l)),
                  Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () => s.removeLine(l['id'] as int)),
                ]),
              ),
          ])),
      const SizedBox(height: 16),
      const Slot('lines.phones'),
      const SizedBox(height: 16),
      const Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What works today', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Muted('Your own number (signed in to your phone provider), Twilio numbers and landlines (through a gateway box on your network) '
              'answer and make calls through this computer. For each line, choose who takes the calls: the AI, you first, or nobody here. '
              'Telnyx API lines are saved now; connect a Telnyx number with “My number, through my provider”.'),
        ]),
      ),
    ]);
  }
}

class _LinePill extends StatelessWidget {
  const _LinePill({required this.line, required this.status});
  final Map<String, Object?> line;
  final SipLineStatus? status;
  @override
  Widget build(BuildContext context) {
    final l = line;
    if (l['provider'] == 'sip') {
      final st = status?.state ?? 'stopped';
      return Pill(
        switch (st) { 'registered' => 'Connected', 'registering' => 'Signing in…', 'failed' => 'Sign-in failed', 'off' => 'Off', _ => 'Not connected' },
        tone: switch (st) { 'registered' => Tone.green, 'registering' => Tone.amber, 'failed' => Tone.red, _ => Tone.neutral },
      );
    }
    return Pill(
        l['provider'] == 'twilio'
            ? (l['status'] == 'verified' ? 'Account verified' : 'Saved')
            : l['provider'] == 'fxo'
                ? (_answersHere(l) ? 'Landline · answered here' : 'Landline')
                : 'Saved · connecting it comes next',
        tone: l['status'] == 'verified' ? Tone.blue : Tone.neutral);
  }
}

/// A `sip` line's sign-in state in words (with the reason when it failed).
class _SipStatusLine extends StatelessWidget {
  const _SipStatusLine({required this.status});
  final SipLineStatus? status;
  @override
  Widget build(BuildContext context) {
    final st = status ?? const SipLineStatus('stopped');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(st.words, style: TextStyle(fontSize: 12.5, color: st.state == 'failed' ? LL.red : context.c.muted)),
    );
  }
}

/// Who takes calls on a line, changed straight from the line's row.
class _LineAnswerControl extends StatefulWidget {
  const _LineAnswerControl({required this.line});
  final Map<String, Object?> line;
  @override
  State<_LineAnswerControl> createState() => _LineAnswerControlState();
}

class _LineAnswerControlState extends State<_LineAnswerControl> {
  String? note;
  bool busy = false;

  Future<void> _apply(LineAnswer a) async {
    final s = context.read<AppModel>();
    setState(() => busy = true);
    final r = await s.setLineAnswer(widget.line['id'] as int, a.mode, ringSeconds: a.ringSeconds);
    if (mounted) {
      setState(() {
        busy = false;
        note = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnswerModePicker(
            key: ValueKey('answer-${widget.line['id']}'),
            value: LineAnswer.of(_cfgOf(widget.line)),
            enabled: !busy,
            showSummary: note == null,
            onChanged: _apply,
          ),
          if (note != null && note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Muted(note!, size: 12)),
        ]),
      );
}

/// Who takes calls on a line: the AI, ring you (then a message), ring you then the AI, or off.
/// With a ring time for the two "ring me" choices.
class AnswerModePicker extends StatefulWidget {
  const AnswerModePicker({super.key, required this.value, required this.onChanged, this.enabled = true, this.showSummary = true});
  final LineAnswer value;
  final ValueChanged<LineAnswer> onChanged;
  final bool enabled, showSummary;
  @override
  State<AnswerModePicker> createState() => _AnswerModePickerState();
}

class _AnswerModePickerState extends State<AnswerModePicker> {
  late final seconds = TextEditingController(text: '${widget.value.ringSeconds}');
  late AnswerMode mode = widget.value.mode;
  String? problem;
  Timer? _wait;

  @override
  void didUpdateWidget(AnswerModePicker old) {
    super.didUpdateWidget(old);
    if (old.value.mode != widget.value.mode) mode = widget.value.mode;
  }

  @override
  void dispose() {
    _wait?.cancel();
    seconds.dispose();
    super.dispose();
  }

  void _secondsChanged(String t) {
    final bad = LineAnswer.ringSecondsProblem(t);
    setState(() => problem = bad);
    _wait?.cancel();
    // (Once typing pauses: "120" isn't sent as "12" first.)
    if (bad == null) _wait = Timer(const Duration(milliseconds: 700), () => widget.onChanged(LineAnswer(mode, ringSeconds: int.parse(t.trim()))));
  }

  @override
  Widget build(BuildContext context) {
    final rings = mode == AnswerMode.ring || mode == AnswerMode.ringThenAi;
    final n = int.tryParse(seconds.text.trim());
    final current = LineAnswer(mode, ringSeconds: problem == null && n != null ? n : widget.value.ringSeconds);
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : .6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Who takes calls', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<AnswerMode>(
              value: mode,
              options: {for (final m in AnswerMode.values) m: m.label},
              onChanged: (m) {
                _wait?.cancel();
                setState(() => mode = m);
                widget.onChanged(LineAnswer(m, ringSeconds: problem == null && n != null ? n : widget.value.ringSeconds));
              },
            ),
          ),
          if (rings) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(mode == AnswerMode.ring ? 'Ring for' : 'The AI answers after', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: TextField(
                  key: const ValueKey('ring-seconds'),
                  controller: seconds,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: _secondsChanged,
                ),
              ),
              const SizedBox(width: 8),
              const Text('seconds', style: TextStyle(fontSize: 13)),
            ]),
            if (problem != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem!, style: const TextStyle(color: LL.red, fontSize: 12))),
          ],
          if (widget.showSummary) ...[
            const SizedBox(height: 4),
            Muted(current.summary, size: 12),
            if (rings) Muted('Rings the phones paired with ${appNameOf(context)} (with ringing on) and the Calls page on this computer.', size: 12),
          ],
        ]),
      ),
    );
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
    final s = context.read<AppModel>();
    final on = _answersHere(widget.line);
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
        if (on && widget.line['provider'] != 'fxo') Muted('Ava answers calls to this number while ${appNameOf(context)} is open. Turn off to give the number back to its previous setup.', size: 12),
      ]),
    );
  }
}

/// What to type into the landline gateway box, so its calls come to this computer.
class _GatewaySettings extends StatelessWidget {
  const _GatewaySettings({required this.line});
  final Map<String, Object?> line;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppModel>();
    final cfg = _cfgOf(line);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.c.canvas, borderRadius: BorderRadius.circular(LL.rSm), border: Border.all(color: context.c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Set up the gateway box (in its web page, under its FXO port)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final (k, v) in s.gatewaySettings(cfg))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 230, child: Muted(k, size: 12)),
              Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 12, fontFamily: LL.mono))),
            ]),
          ),
        const SizedBox(height: 4),
        const Muted('The box\'s address must stay the same: give it a fixed IP in your router. Only that box, with this login, can ring in.', size: 11.5),
      ]),
    );
  }
}

/// Adds a phone line, or edits [line].
Future<void> showLineDialog(BuildContext context, {Map<String, Object?>? line}) => showDialog(context: context, builder: (_) => LineDialog(line: line));

class LineDialog extends StatefulWidget {
  const LineDialog({super.key, this.line});

  /// The saved line being edited (null: adding one).
  final Map<String, Object?>? line;
  @override
  State<LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<LineDialog> {
  late String provider = '${widget.line?['provider'] ?? 'sip'}';
  late final Map<String, dynamic> saved = widget.line == null ? {} : _cfgOf(widget.line!);
  final ctrls = <String, TextEditingController>{};
  String? check;
  bool checking = false, verified = false, testing = false;
  bool? tested; // the last connection test worked
  List<String> numbers = [];
  late LineAnswer answer = LineAnswer.of(saved);
  late String preset = SipLine.of(saved).preset;
  late String transport = widget.line == null ? 'tls' : SipLine.of(saved).transport;

  bool get editing => widget.line != null;

  TextEditingController _c(String k) => ctrls.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    if (!editing) return;
    if (provider == 'sip') {
      final l = SipLine.of(saved);
      _c('number').text = l.number;
      _c('domain').text = l.domain;
      _c('port').text = l.port == null ? '' : '${l.port}';
      _c('username').text = l.username;
      _c('authUsername').text = l.authUsername;
      _c('outboundProxy').text = l.outboundProxy;
    } else {
      // (Secrets stay empty: leaving them empty keeps the saved ones.)
      for (final f in providers[provider]?.$2 ?? const <(String, String, bool)>[]) {
        if (!f.$3) _c(f.$1).text = '${saved[f.$1] ?? ''}';
      }
    }
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

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
        final sid = _c('sid').text.trim(), token = _secret('token'), keySid = _c('keySid').text.trim();
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
            headers: {'Authorization': 'Bearer ${_secret('apiKey')}'});
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

  /// A secret field: what was typed, else (editing) the saved one.
  String _secret(String k) => _c(k).text.trim().isNotEmpty ? _c(k).text.trim() : '${saved[k] ?? ''}';

  /// What's wrong with the Twilio details, if anything (said in the dialog, not behind it).
  String? _twilioProblem() {
    final sid = _c('sid').text.trim(), token = _secret('token'), keySid = _c('keySid').text.trim();
    if (sid.startsWith('SK')) return 'That’s an API key SID. Put it in “API key SID”, and put your Account SID (starts with AC) in the first box.';
    if (!RegExp(r'^AC[0-9a-fA-F]{32}$').hasMatch(sid)) return 'The Account SID starts with AC and has 34 characters. Copy it from the Twilio console home page.';
    if (token.isEmpty) return 'Add the Auth token (or the API key secret).';
    if (keySid.isNotEmpty && !keySid.startsWith('SK')) return 'The API key SID starts with SK. Leave it empty if you use the Auth token.';
    return null;
  }

  /// "+44 1234 567 890", "(415) 555-0100" → "+441234567890". Numbers need the country code.
  static String normalizeNumber(String n) => normalizePhoneNumber(n);

  /// The `sip` line as typed (the password empty when editing and not changed).
  SipLine _sipLine() => SipLine(
        number: normalizeNumber(_c('number').text),
        domain: _c('domain').text.trim().replaceFirst(RegExp(r'^sips?:', caseSensitive: false), ''),
        port: int.tryParse(_c('port').text.trim()),
        transport: transport,
        username: _c('username').text.trim(),
        authUsername: _c('authUsername').text.trim(),
        password: _c('password').text,
        outboundProxy: _c('outboundProxy').text.trim(),
        preset: preset,
      );

  bool get _hasSavedPassword => SipLine.of(saved).password.isNotEmpty;

  Future<void> _test() async {
    final s = context.read<AppModel>();
    final line = _sipLine();
    final bad = line.problem(needPassword: !_hasSavedPassword);
    if (bad != null) {
      return setState(() {
        tested = false;
        check = bad;
      });
    }
    setState(() {
      testing = true;
      check = 'Signing in to your provider… (the first time, this computer also sets up the phone gateway, which takes a minute)';
      tested = null;
    });
    final r = await s.testSipLine(line.toConfig(), lineId: widget.line?['id'] as int?);
    if (!mounted) return;
    setState(() {
      testing = false;
      tested = r.ok;
      check = r.result;
    });
  }

  void _usePreset(String id) {
    final p = sipPresets.firstWhere((x) => x.id == id, orElse: () => sipPresets.first);
    setState(() {
      preset = p.id;
      if (p.domain.isNotEmpty) _c('domain').text = p.domain;
      if (p.port != null) _c('port').text = '${p.port}';
      transport = p.transport;
      check = null;
      tested = null;
    });
  }

  Future<void> _save() async {
    final s = context.read<AppModel>();
    final (label, fields) = providers[provider]!;
    String? problem;
    Map<String, dynamic> cfg;
    String number;
    if (provider == 'sip') {
      final line = _sipLine();
      problem = line.problem(needPassword: !_hasSavedPassword);
      final keep = line.password.isEmpty ? {'password': SipLine.of(saved).password} : const <String, dynamic>{};
      // (Older keys of this line type are dropped: server, sipUser, sipPass.)
      cfg = {...saved, ...line.toConfig(), ...keep}..removeWhere((k, _) => const {'server', 'sipUser', 'sipPass'}.contains(k));
      if (line.port == null) cfg.remove('port');
      for (final k in ['authUsername', 'outboundProxy']) {
        if ('${line.toConfig()[k] ?? ''}'.isEmpty) cfg.remove(k);
      }
      number = line.number;
    } else {
      cfg = {...saved, for (final f in fields) f.$1: f.$3 ? _secret(f.$1) : _c(f.$1).text.trim()};
      number = normalizeNumber('${cfg['number']}');
      if (provider == 'twilio') problem = _twilioProblem();
      if (problem == null && number.isEmpty) problem = 'Add the phone number.';
      if (problem == null && provider != 'fxo' && !number.startsWith('+')) {
        problem = 'Write the number with its country code, e.g. +44 7700 900123 (not starting with 0).';
      }
      if (problem == null && verified && numbers.isNotEmpty && !numbers.contains(number)) {
        problem = 'That number isn’t in this Twilio account. Pick one of: ${numbers.join(', ')}';
      }
    }
    if (problem != null) return setState(() => check = problem);
    cfg['number'] = number;
    final before = LineAnswer.of(saved);
    cfg = answer.applyTo(cfg);
    final row = {
      'provider': provider,
      'label': editing ? '${widget.line!['label']}' : (provider == 'sip' ? 'My number' : label),
      'number': number,
      'config': jsonEncode(cfg),
      'status': verified || (editing && widget.line!['status'] == 'verified') ? 'verified' : 'saved',
    };
    final int id;
    if (editing) {
      id = widget.line!['id'] as int;
      await s.db.update('lines', id, row);
      await s.log('Changed phone line ${row['label']} $number');
    } else {
      id = await s.db.insert('lines', row);
      await s.log('Added phone line ${row['label']} $number');
    }
    s.refresh();
    if (mounted) Navigator.pop(context);
    if (provider == 'sip') {
      s.toast('Connecting $number through your provider…');
      final r = await s.connectLine(id);
      if (r.isNotEmpty) s.toast(r);
    } else if (editing && answer.mode != before.mode && answer.mode == AnswerMode.off) {
      // (Off on a Twilio line or a landline: it stops answering here.)
      final r = await s.setLineAnswer(id, answer.mode, ringSeconds: answer.ringSeconds);
      if (r.isNotEmpty) s.toast(r);
    }
  }

  Widget _sipForm() {
    final p = sipPresets.firstWhere((x) => x.id == preset, orElse: () => sipPresets.first);
    Widget field(String k, String label, {String? hint, String? placeholder}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Field(label: label, hint: hint, child: TextField(key: ValueKey('sip-$k'), controller: _c(k), decoration: InputDecoration(hintText: placeholder))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Muted('Your existing number keeps working as it is: this computer signs in to your phone provider like a desk phone would. '
          'No hardware, no moving your number. Your provider must offer a SIP login (“SIP device”, “SIP phone” or “SIP credentials”).'),
      const SizedBox(height: 14),
      Field(
        label: 'Your provider',
        child: Dropdown<String>(value: preset, items: {for (final x in sipPresets) x.id: x.name}, onChanged: _usePreset),
      ),
      if (p.note.isNotEmpty || p.id != 'generic') ...[
        const SizedBox(height: 6),
        Muted('${p.note}${p.id == 'generic' ? '' : ' These are the usual settings: check them with your provider.'}', size: 12),
      ],
      const SizedBox(height: 12),
      field('number', 'Your phone number', placeholder: '+44 7700 900123'),
      field('domain', 'SIP server (registrar or domain)', placeholder: 'sip.example.com'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: field('port', 'Port', placeholder: transport == 'tls' ? '5061' : '5060')),
        const SizedBox(width: 16),
        Expanded(
          child: Field(
            label: 'Connection',
            hint: transport == 'udp' ? 'UDP may need your router to let calls in. Use TLS or TCP if your provider offers them.' : null,
            child: Segmented<String>(
              value: transport,
              options: const {'tls': 'TLS (secure)', 'tcp': 'TCP', 'udp': 'UDP'},
              onChanged: (t) => setState(() => transport = t),
            ),
          ),
        ),
      ]),
      field('username', 'SIP username'),
      field('authUsername', 'Authentication username (optional)', hint: 'Only if your provider gives a separate one for signing in.'),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Field(
          label: 'SIP password',
          hint: editing && _hasSavedPassword ? 'Leave empty to keep the saved password.' : null,
          child: PasswordField(key: const ValueKey('sip-password'), controller: _c('password')),
        ),
      ),
      field('outboundProxy', 'Outbound proxy (optional)', placeholder: 'proxy.example.com:5060', hint: 'Only if your provider names one.'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fields = providers[provider]!.$2;
    final good = provider == 'sip' ? tested == true : verified;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'Edit phone line' : 'Add phone line', style: displayStyle(context, 22)),
            const SizedBox(height: 16),
            if (!editing) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in providers.entries)
                  ChoiceChip(
                    label: Text(e.value.$1),
                    selected: provider == e.key,
                    onSelected: (_) => setState(() {
                      provider = e.key;
                      check = null;
                      verified = false;
                      tested = null;
                      numbers = [];
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            if (provider == 'sip')
              _sipForm()
            else
              for (final f in fields) ...[
                Field(
                  label: f.$2,
                  hint: f.$3 && editing && '${saved[f.$1] ?? ''}'.isNotEmpty ? 'Leave empty to keep the saved one.' : null,
                  child: TextField(controller: _c(f.$1), obscureText: f.$3),
                ),
                const SizedBox(height: 12),
              ],
            if (provider == 'fxo')
              const Muted('Set the FXO box to send calls to this computer on port 5080, with SIP registration off and at least 2 rings for caller ID.'),
            const SizedBox(height: 4),
            AnswerModePicker(value: answer, onChanged: (a) => setState(() => answer = a)),
            const SizedBox(height: 10),
            Muted(provider == 'sip'
                ? 'Saved in the local database on this computer only. Your password goes only to your provider.'
                : 'Saved in the local database on this computer only.'),
            if (check != null) ...[
              const SizedBox(height: 10),
              Text(check!, key: const ValueKey('line-check'), style: TextStyle(color: testing ? context.c.muted : (good ? LL.green : LL.red), fontSize: 13)),
            ],
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
              if (provider == 'sip') Btn(testing ? 'Testing…' : 'Test connection', icon: Icons.network_check, onPressed: testing ? null : _test),
              const Spacer(),
              Btn('Cancel', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Btn(editing ? 'Save changes' : 'Save line', kind: BtnKind.primary, onPressed: _save),
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
    final s = context.watch<AppModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead('Settings'),
      Text('AI engine', style: displayStyle(context, 17)),
      const SizedBox(height: 10),
      const Slot('engine.setup'),
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
            if (!s.isHosted) Btn('Open data folder', icon: Icons.folder_open_outlined, small: true, onPressed: s.openDataFolder),
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
    final s = context.watch<AppModel>();
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
