import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
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
    final start = Panel(
      child: Row(children: [
        const Icon(Icons.record_voice_over_outlined),
        const SizedBox(width: 12),
        const Expanded(child: Muted('Have a pretend customer phone your assistant: watch the conversation live, then check your app’s website.')),
        Btn('Run a test call', kind: BtnKind.primary, onPressed: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const TestCallDialog())),
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
                  for (final t in (c['turns'] as List? ?? []))
                    if ('$t'.trim() != 'AI:') _bubble(ctx, '$t'),
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

Widget _bubble(BuildContext ctx, String line) {
  final ai = line.startsWith('AI:');
  final text = line.substring(line.indexOf(':') + 1).trim();
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: ai ? MainAxisAlignment.start : MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: ai ? ctx.c.amberSoft : ctx.c.blueSoft, borderRadius: BorderRadius.circular(LL.r)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ai ? 'AI' : 'Caller', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ai ? ctx.c.amberInk : ctx.c.blueInk)),
            const SizedBox(height: 2),
            SelectableText(text),
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
  final lines = <(String, String)>[];
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
        onLine: (who, text) {
          if (!mounted) return;
          setState(() => lines.add((who, text)));
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
                    for (final (who, text) in lines)
                      if (who == 'note') Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Pill(text, tone: Tone.blue))) else _bubble(context, '${who == 'ai' ? 'AI' : 'CALLER'}: $text'),
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
