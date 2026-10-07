import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/apps/app_templates.dart';
import '../../state/app_state.dart';
import '../../state/scenario_runner.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Results of the phone-call test scenarios (app/test/scenarios): each one as the conversation
/// it was, what the AI did in the business's app, and what was checked on its website.
/// Reads `<data folder>/test-runs/*.jsonl` and refreshes while a run is going.
class TestRunsSection extends StatefulWidget {
  const TestRunsSection({super.key});
  @override
  State<TestRunsSection> createState() => _TestRunsSectionState();
}

class _TestRunsSectionState extends State<TestRunsSection> {
  List<Map<String, dynamic>> runs = [];
  String show = 'all', app = 'all';
  int limit = 60;
  Timer? _tick;
  int _size = -1;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Directory get _dir => Directory('${File(context.read<AppState>().db.path).parent.path}/test-runs');

  Future<void> _load() async {
    if (!mounted) return;
    final dir = _dir;
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList();
    final size = files.fold<int>(0, (n, f) => n + f.lengthSync());
    if (size == _size) return;
    _size = size;
    final byId = <String, Map<String, dynamic>>{};
    for (final f in files) {
      for (final l in await f.readAsLines()) {
        if (l.trim().isEmpty) continue;
        try {
          final r = (jsonDecode(l) as Map).cast<String, dynamic>();
          byId['${r['id']}'] = r; // the latest run of a scenario wins
        } catch (_) {}
      }
    }
    if (mounted) setState(() => runs = byId.values.toList().reversed.toList());
  }

  static String _title(String s) => s.replaceAll('journey_', '').replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final start = Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.science_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Muted(st.scenarioRun != null
                ? st.scenarioStatus
                : 'Test your assistant on your own apps: pretend customers phone it, and each booking or order is checked on the app’s website.${st.scenarioStatus.isEmpty ? '' : ' ${st.scenarioStatus}.'}'),
          ),
          const SizedBox(width: 8),
          if (st.scenarioRun != null)
            Btn('Stop', kind: BtnKind.danger, onPressed: st.stopScenarios)
          else ...[
            Btn('Run a test call', onPressed: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const TestCallDialog())),
            const SizedBox(width: 8),
            Btn('Run test scenarios', kind: BtnKind.primary, onPressed: () => showDialog(context: context, builder: (_) => const _RunScenariosDialog())),
          ],
        ]),
      ]),
    );
    if (runs.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        start,
        const SizedBox(height: 12),
        const Panel(child: EmptyState(icon: Icons.science_outlined, title: 'No test scenarios yet', body: 'Results of the phone-call scenarios (app/test/scenarios) show up here, live.')),
      ]);
    }
    final passed = runs.where((r) => r['pass'] == true).length;
    final apps = <String, List<Map<String, dynamic>>>{};
    for (final r in runs) {
      apps.putIfAbsent('${r['app']}', () => []).add(r);
    }
    final shown = [
      for (final r in runs)
        if ((show == 'all' || (show == 'failed') != (r['pass'] == true)) && (app == 'all' || r['app'] == app)) r,
    ];
    final calls = runs.fold<int>(0, (n, r) => n + ((r['calls'] as List?)?.where((c) => (c as Map).containsKey('turns')).length ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      start,
      const SizedBox(height: 12),
      const LiveTestPanel(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('$passed of ${runs.length} test scenarios passed', style: displayStyle(context, 20)),
            const SizedBox(width: 12),
            Pill('${(100 * passed / runs.length).round()}%', tone: passed / runs.length >= .85 ? Tone.green : passed / runs.length >= .6 ? Tone.amber : Tone.red),
            const Spacer(),
            Muted('$calls phone calls', mono: true),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in apps.entries)
              () {
                final ok = e.value.where((r) => r['pass'] == true).length;
                final rate = ok / e.value.length;
                return InkWell(
                  onTap: () => setState(() => app = app == e.key ? 'all' : e.key),
                  child: Pill('${e.key} $ok/${e.value.length}', tone: app == e.key ? Tone.blue : rate >= .85 ? Tone.green : rate >= .6 ? Tone.amber : Tone.red),
                );
              }(),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Segmented(value: show, options: const {'all': 'All', 'failed': 'Failed', 'passed': 'Passed'}, onChanged: (v) => setState(() => show = v)),
        const SizedBox(width: 12),
        if (app != 'all') Btn('Showing $app ✕', onPressed: () => setState(() => app = 'all')),
      ]),
      const SizedBox(height: 12),
      Section(title: '${shown.length} scenario${shown.length == 1 ? '' : 's'} · newest first', children: [
        for (final r in shown.take(limit))
          Tile(
            last: r == shown.take(limit).last,
            onTap: () => showTestRun(context, r),
            leading: LogoBox(child: Icon(r['pass'] == true ? Icons.check_circle_outline : Icons.error_outline, color: r['pass'] == true ? context.c.greenInk : context.c.redInk)),
            title: Text('${r['app']} · ${_title('${r['intent']}')}'),
            subtitle: Muted(r['pass'] == true ? _firstLine(r) : '${(r['failures'] as List).first}', size: 12.5),
            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Pill('${r['setup']} · ${'${r['style'] ?? ''}'.replaceAll('_', ' ')}'),
              const SizedBox(height: 4),
              Muted('${r['id']} · ${r['seconds']}s', mono: true, size: 11),
            ]),
          ),
        if (shown.length > limit)
          Padding(padding: const EdgeInsets.all(12), child: Center(child: Btn('Show more', onPressed: () => setState(() => limit += 100)))),
      ]),
    ]);
  }

  static String _firstLine(Map<String, dynamic> r) {
    for (final c in (r['calls'] as List? ?? [])) {
      for (final t in ((c as Map)['turns'] as List? ?? [])) {
        if ('$t'.startsWith('CALLER:')) return '$t'.substring(8);
      }
    }
    return 'Website / tools only';
  }
}

/// One scenario: every call as a conversation, what the AI did in the app, and the checks.
void showTestRun(BuildContext context, Map<String, dynamic> r) {
  final calls = (r['calls'] as List? ?? []).cast<Map>();
  final failures = (r['failures'] as List? ?? []).cast<Object?>();
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${r['app']} · ${'${r['intent']}'.replaceAll('journey_', '').replaceAll('_', ' ')}', style: displayStyle(ctx, 22))),
              Pill(r['pass'] == true ? 'Passed' : 'Failed', tone: r['pass'] == true ? Tone.green : Tone.red),
            ]),
            Muted('${r['id']} · agents: ${r['setup']} · caller: ${'${r['style'] ?? ''}'.replaceAll('_', ' ')} · ${r['seconds']}s', mono: true),
            const SizedBox(height: 12),
            if (failures.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: ctx.c.redSoft, borderRadius: BorderRadius.circular(LL.r)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow('What the check found'),
                  const SizedBox(height: 4),
                  for (final f in failures) SelectableText('• $f', style: TextStyle(color: ctx.c.redInk, fontSize: 13)),
                ]),
              ),
            Expanded(
              child: ListView(children: [
                for (final (i, c) in calls.indexed) ...[
                  if (calls.length > 1 || !c.containsKey('turns'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Eyebrow(c.containsKey('turns')
                          ? 'Call ${i + 1} · from caller ${c['from'] ?? 'A'} · ${c['seconds'] ?? 0}s'
                          : 'Step ${i + 1} · website form "${c['web']}" → ${c['code']}'),
                    ),
                  if (c['ai_ms'] is Map)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Muted(
                          'AI answers: ${_s((c['ai_ms'] as Map)['avg'])} on average, slowest ${_s((c['ai_ms'] as Map)['max'])} · first words after ${_s((c['ai_ms'] as Map)['first_avg'])} on average, at worst ${_s((c['ai_ms'] as Map)['first_max'])}',
                          size: 12.5),
                    ),
                  for (final (j, t) in (c['turns'] as List? ?? []).indexed)
                    if ('$t'.trim() != 'AI:') _bubble(ctx, '$t', time: j < ((c['times'] as List?)?.length ?? 0) ? ((c['times'] as List)[j] as Map) : null),
                  if ((c['passed_to'] as List? ?? []).isNotEmpty) Muted('Passed the call to: ${(c['passed_to'] as List).join(', ')}', size: 12.5),
                  if ((c['tools'] as List? ?? []).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Eyebrow('What the AI did in the app'),
                    const SizedBox(height: 4),
                    for (final t in (c['tools'] as List))
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: '$t'.contains('→ ERROR') ? ctx.c.redSoft : ctx.c.canvas,
                          border: Border.all(color: ctx.c.line),
                          borderRadius: BorderRadius.circular(LL.rSm),
                        ),
                        child: SelectableText('$t', style: const TextStyle(fontFamily: LL.mono, fontSize: 11.5)),
                      ),
                  ],
                  if (c['saved'] != null) ...[
                    const SizedBox(height: 6),
                    Eyebrow('On the website afterwards'),
                    SelectableText(const JsonEncoder.withIndent('  ').convert(c['saved']), style: const TextStyle(fontFamily: LL.mono, fontSize: 11.5)),
                  ],
                  if (!c.containsKey('turns') && c['body'] != null) SelectableText('${c['body']}', style: const TextStyle(fontFamily: LL.mono, fontSize: 11.5)),
                  const Divider(height: 24),
                ],
              ]),
            ),
            Align(alignment: Alignment.centerRight, child: Btn('Close', kind: BtnKind.primary, onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      ),
    ),
  );
}

/// Milliseconds as "3.2 s".
String _s(Object? ms) => ms is num ? '${(ms / 1000).toStringAsFixed(1)} s' : '–';

/// Slow enough that a caller notices (the test run's limits: 5 s to first words, 25 s in all).
bool _slow(Map? t) => t != null && (((t['first_ms'] as num?) ?? 0) > 5000 || ((t['ms'] as num?) ?? 0) > 25000);

Widget _bubble(BuildContext ctx, String line, {Map? time}) {
  // A hand-over in one AI turn: the first agent, the hold music, then the teammate in their own voice.
  final hold = RegExp(r'\s*⏸ \(on hold\) ([^:]+): ').firstMatch(line);
  if (line.startsWith('AI:') && hold != null) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (line.substring(3, hold.start).trim().isNotEmpty) _bubble(ctx, line.substring(0, hold.start), time: time),
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Pill('♪ on hold, passed to ${hold[1]}', tone: Tone.blue))),
      _bubble(ctx, 'AI (${hold[1]}): ${line.substring(hold.end)}'),
    ]);
  }
  final ai = line.startsWith('AI');
  final text = line.substring(line.indexOf(':') + 1).trim();
  final who = RegExp(r'^AI \(([^)]+)\)').firstMatch(line)?.group(1);
  final when = [
    if (time?['at'] != null) '${time!['at']}',
    if (time?['stt_ms'] != null) 'heard in ${_s(time!['stt_ms'])} (${((time['heard_match'] as num? ?? 0) * 100).round()}% right)',
    if (time?['ms'] != null) 'answered in ${_s(time!['ms'])} · first words after ${_s(time['first_ms'])}',
    if (time?['to_answer_ms'] != null) 'caller waited ${_s(time!['to_answer_ms'])} for the answer',
    if (time?['ai_match'] != null) 'voice ready in ${_s(time!['voice_first_ms'])}, ${((time['ai_match'] as num) * 100).round()}% clear',
  ].join(' · ');
  final saidInstead = time?['said'] != null && '${time!['said']}'.trim() != text ? '${time['said']}' : null;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: ai ? MainAxisAlignment.start : MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: ai ? ctx.c.amberSoft : ctx.c.blueSoft, borderRadius: BorderRadius.circular(LL.r)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(ai ? (who ?? 'AI') : 'Caller', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ai ? ctx.c.amberInk : ctx.c.blueInk)),
              if (when.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(when,
                      style: TextStyle(fontFamily: LL.mono, fontSize: 10.5, color: _slow(time) ? ctx.c.redInk : ctx.c.muted, fontWeight: _slow(time) ? FontWeight.w700 : FontWeight.w400)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            SelectableText(text),
            if (saidInstead != null) Muted('(they said: $saidInstead)', size: 11.5),
          ]),
        ),
      ),
    ]),
  );
}


/// Ready-made things a test customer can ring about.
const _presets = <(String, String, List<String>)>[
  ('Book a table', 'Book a table for 2 tomorrow at 7pm.', ['Day: tomorrow', 'Time: 7pm', 'People: 2']),
  ('Order for delivery', 'Order 2 Margherita pizzas and 1 tiramisu for delivery.', ['You want: 2 Margherita, 1 tiramisu', 'Delivery to: 12 Mill Lane', 'Postcode: E1 6AN']),
  ('Order for collection', 'Order 1 Diavola and 2 San Pellegrino to collect at 6:30pm.', ['You want: 1 Diavola, 2 San Pellegrino', 'You will collect it at 6:30pm']),
  ('Change my booking', 'You booked a table for tomorrow; move it to 9pm, same day.', ['Your booking: tomorrow', 'New time: 9pm', 'You booked with the number you are calling from']),
  ('Cancel my booking', 'Cancel your table booking for tomorrow.', ['Your booking: tomorrow', 'You booked with the number you are calling from']),
  ('Book a haircut', 'Book a skin fade on Saturday at 10am with Tony.', ['Service: skin fade', 'Day: Saturday', 'Time: 10am', 'Barber: Tony']),
  ('Ask a price', 'Ask how much your most popular item or service costs. You do not want to book or order.', []),
  ('Speak to a person', 'Ask to speak to the manager about a compliment.', ['It is about a compliment']),
];

/// Runs one test call and shows it as it happens.
class TestCallDialog extends StatefulWidget {
  const TestCallDialog({super.key});
  @override
  State<TestCallDialog> createState() => _TestCallDialogState();
}

class _TestCallDialogState extends State<TestCallDialog> {
  final goal = TextEditingController(text: _presets.first.$2);
  final facts = TextEditingController(text: _presets.first.$3.join('\n'));
  final name = TextEditingController(text: 'Alex Morgan');
  final number = TextEditingController(text: '+447700900999');
  final lines = <(String, String, Map<String, Object?>)>[];
  final scroll = ScrollController();
  bool running = false, stopped = false, done = false;
  String? error;

  Future<void> _run() async {
    final s = context.read<AppState>();
    setState(() {
      running = true;
      lines.clear();
      error = null;
    });
    try {
      await s.testCall(
        goal: goal.text.trim(),
        facts: ['Your name: ${name.text.trim()}', ...facts.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)],
        number: number.text.trim(),
        stop: () => stopped,
        onLine: (who, text, time) {
          if (!mounted) return;
          setState(() => lines.add((who, text, time)));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          });
        },
      );
    } catch (e) {
      error = '$e';
    }
    if (mounted) {
      setState(() {
        running = false;
        done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Test call', style: displayStyle(context, 22)),
              const Muted('A local AI plays the customer and phones your assistant the way a real caller does. Bookings and orders go into your app.'),
              const SizedBox(height: 14),
              if (lines.isEmpty && !running) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in _presets)
                    InkWell(
                      onTap: () => setState(() {
                        goal.text = p.$2;
                        facts.text = p.$3.join('\n');
                      }),
                      child: Pill(p.$1, tone: goal.text == p.$2 ? Tone.blue : Tone.neutral),
                    ),
                ]),
                const SizedBox(height: 12),
                Field(label: 'What the customer wants', child: TextField(controller: goal, maxLines: 2)),
                const SizedBox(height: 8),
                Field(label: 'What they know (one per line)', child: TextField(controller: facts, maxLines: 4)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Field(label: 'Their name', child: TextField(controller: name))),
                  const SizedBox(width: 12),
                  Expanded(child: Field(label: 'Calling from (use the same number to change or cancel later)', child: TextField(controller: number))),
                ]),
              ] else
                Expanded(
                  child: ListView(controller: scroll, children: [
                    for (final (who, text, time) in lines)
                      if (who == 'note') Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Pill(text, tone: Tone.blue))) else _bubble(context, '${who == 'ai' ? 'AI' : 'CALLER'}: $text', time: time),
                    if (running) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
                    if (done) Padding(padding: const EdgeInsets.all(8), child: Muted(error ?? 'Call finished — it is saved in Calls → Tests. Open your app’s manager page to see what was booked or ordered.')),
                  ]),
                ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (running) Btn('Hang up', kind: BtnKind.danger, onPressed: () => setState(() => stopped = true)),
                if (!running) Btn('Close', onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                if (!running) Btn(done ? 'Call again' : 'Start the call', kind: BtnKind.primary, onPressed: () {
                  stopped = false;
                  done = false;
                  _run();
                }),
              ]),
            ]),
          ),
        ),
      );
}


/// What the test run is doing right now: one per call going on (written by the runners after every turn).
List<Map<String, dynamic>> readLiveTests(AppState s) {
  final dir = Directory('${File(s.db.path).parent.path}/test-runs');
  if (!dir.existsSync()) return [];
  final out = <Map<String, dynamic>>[];
  for (final f in dir.listSync().whereType<File>().where((f) => RegExp(r'/live(-\d+)?\.json$').hasMatch(f.path)).toList()..sort((a, b) => a.path.compareTo(b.path))) {
    try {
      if (DateTime.now().difference(f.lastModifiedSync()) > const Duration(minutes: 4)) continue;
      out.add((jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
    } catch (_) {}
  }
  return out;
}

Map<String, dynamic>? readLiveTest(AppState s) => readLiveTests(s).firstOrNull;

/// The call being tested right now, line by line.
class LiveTestPanel extends StatefulWidget {
  const LiveTestPanel({super.key});
  @override
  State<LiveTestPanel> createState() => _LiveTestPanelState();
}

class _LiveTestPanelState extends State<LiveTestPanel> {
  List<Map<String, dynamic>> lives = [];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _read();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  void _read() {
    if (!mounted) return;
    final l = readLiveTests(context.read<AppState>());
    if (jsonEncode(l) != jsonEncode(lives)) setState(() => lives = l);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final l in lives) _one(context, l)]);

  Widget _one(BuildContext context, Map<String, dynamic> l) {
    final turns = (l['turns'] as List? ?? []).cast<Object?>();
    final tools = (l['tools'] as List? ?? []).cast<Object?>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        borderColor: context.c.blueInk,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(
                child: Text('${(l['lines'] as num? ?? 1) > 1 ? 'Line ${l['line']} · ' : ''}Testing now: ${l['app']} · ${'${l['intent']}'.replaceAll('journey_', '').replaceAll('_', ' ')}',
                    style: displayStyle(context, 18))),
            Pill('${l['done']} of ${l['total']} done · ${l['passed']} passed', tone: Tone.blue),
          ]),
          const SizedBox(height: 4),
          Muted('${l['id']} · agents: ${l['setup']} · caller: ${'${l['style'] ?? ''}'.replaceAll('_', ' ')}${(l['calls'] as num? ?? 1) > 1 ? ' · call ${l['call']} of ${l['calls']}' : ''}', mono: true, size: 12),
          if ('${l['goal'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Muted('The caller wants to: ${l['goal']}', size: 13)),
          const SizedBox(height: 12),
          for (final (j, t) in turns.indexed)
            if ('$t'.trim() != 'AI:') _bubble(context, '$t', time: j < ((l['times'] as List?)?.length ?? 0) ? ((l['times'] as List)[j] as Map) : null),
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 4),
            Eyebrow('What the AI did in the app'),
            const SizedBox(height: 4),
            for (final t in tools) Padding(padding: const EdgeInsets.only(bottom: 3), child: SelectableText('$t', style: TextStyle(fontFamily: LL.mono, fontSize: 11.5, color: '$t'.contains('ERROR') ? context.c.redInk : context.c.muted))),
          ],
        ]),
      ),
    );
  }
}

/// On the home page: a test run is going (or has results) — one tap to watch it.
class TestRunBanner extends StatefulWidget {
  const TestRunBanner({super.key});
  @override
  State<TestRunBanner> createState() => _TestRunBannerState();
}

class _TestRunBannerState extends State<TestRunBanner> {
  Map<String, dynamic>? live;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _read();
    _tick = Timer.periodic(const Duration(seconds: 3), (_) => _read());
  }

  void _read() {
    if (!mounted) return;
    final l = readLiveTest(context.read<AppState>());
    if (jsonEncode(l) != jsonEncode(live)) setState(() => live = l);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = live;
    if (l == null) return const SizedBox.shrink();
    final last = (l['turns'] as List? ?? []).lastOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Panel(
        borderColor: context.c.blueInk,
        child: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Test calls running${(l['lines'] as num? ?? 1) > 1 ? ' (${l['lines']} at the same time)' : ''}: ${l['done']} of ${l['total']} done, ${l['passed']} passed',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Muted('Now: ${l['app']} · ${'${l['intent']}'.replaceAll('journey_', '').replaceAll('_', ' ')}${last == null ? '' : ' — $last'}', size: 12.5),
            ]),
          ),
          const SizedBox(width: 12),
          Btn('Watch', kind: BtnKind.primary, onPressed: () => context.read<AppState>().openTests()),
        ]),
      ),
    );
  }
}


/// Which test scenarios to run in your own apps.
class _RunScenariosDialog extends StatefulWidget {
  const _RunScenariosDialog();
  @override
  State<_RunScenariosDialog> createState() => _RunScenariosDialogState();
}

class _RunScenariosDialogState extends State<_RunScenariosDialog> {
  ScenarioPick pick = ScenarioPick.quick;
  String app = 'barber';
  int parallel = 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Run test scenarios'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Muted('Pretend customers phone your assistant. Bookings and orders go into your own apps’ websites (an app it needs and you don’t have yet, '
                'like the barber shop, is made for you in Build an app). Every call is checked afterwards; you can watch it live here.'),
            const SizedBox(height: 14),
            for (final (v, label, note) in [
              (ScenarioPick.quick, 'Quick check', 'One of each kind of call for every app (about 70 calls, about an hour)'),
              (ScenarioPick.app, 'One app', 'Every scenario for one business'),
              (ScenarioPick.journeys, 'Call-backs and teams', 'Book, call back to change, someone else tries to cancel, cancel; switching apps; agent teams; skills (272)'),
              (ScenarioPick.challenges, 'Hard calls', 'Long and messy: five-minute calls with many questions, detours, changing their mind, off-topic, rude callers, tricks, privacy, and 8 other languages (479)'),
              (ScenarioPick.all, 'Everything', 'All 1,901 scenarios (a day or more)'),
            ])
              InkWell(
                onTap: () => setState(() => pick = v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(pick == v ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: pick == v ? context.c.blueInk : context.c.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted(note, size: 12.5),
                      ]),
                    ),
                  ]),
                ),
              ),
            if (pick == ScenarioPick.app)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Dropdown<String>(value: app, items: {for (final t in appTemplates) t.id: t.name}, onChanged: (v) => setState(() => app = v)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Calls at the same time', style: TextStyle(fontWeight: FontWeight.w600))),
              Segmented<int>(value: parallel, options: const {1: 'One', 2: 'Two', 3: 'Three', 4: 'Four'}, onChanged: (v) => setState(() => parallel = v)),
            ]),
            const Muted('Several callers at once (each for a different business), to check the lines stay fast together.', size: 12.5),
          ]),
        ),
        actions: [
          Btn('Cancel', onPressed: () => Navigator.pop(context)),
          Btn('Start', kind: BtnKind.primary, onPressed: () {
            final s = context.read<AppState>();
            Navigator.pop(context);
            s.runScenarios(pick, app: app, parallel: parallel).catchError((Object e) => s.toast('$e'));
          }),
        ],
      );
}
