import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/apps/app_spec.dart';
import '../../services/apps/apps_manager.dart';
import '../../services/companion/host_server.dart';
import '../../services/system.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// A model that can see pictures, offered when none is downloaded.
const _visionModel = 'gemma3:4b';

const _ideas = [
  ('Restaurant', 'I have a restaurant. Customers should search the menu, order food and choose their table. '
      'As the manager I set the tables, the opening and closing times, and the list of food with prices.'),
  ('Hair salon', 'A hair salon. Customers see our services and prices and book an appointment with a stylist. '
      'I manage stylists, services and see all bookings.'),
  ('Gym classes', 'A small gym. Members see the class timetable and sign up for a class. I add classes, trainers and limits.'),
  ('Shop orders', 'A small shop. Customers browse products with photos and prices and place an order for pickup. I manage products and stock.'),
];

/// "Build an app": describe what you need, the AI builds it step by step, and it runs here.
class BuilderPage extends StatefulWidget {
  const BuilderPage({super.key});
  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  int? openId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final job = s.apps.job;
    if (job != null) return _Wizard(job: job, onOpen: (id) => setState(() => openId = id));
    if (openId != null) return _AppDetail(id: openId!, onBack: () => setState(() => openId = null));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Build an app',
          description: 'Describe the system you need — a website for your customers, a manager page, and tools Ava can use on calls. '
              'Your AI plans it and builds it piece by piece, and it runs on this computer.',
          actions: [Btn('New app', icon: Icons.add, kind: BtnKind.primary, onPressed: () => s.apps.newJob())]),
      FutureBuilder(
        future: s.apps.apps(),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (snap.hasData && list.isEmpty) {
            return Panel(
              child: EmptyState(
                icon: Icons.auto_fix_high_outlined,
                title: 'No apps yet',
                body: 'For example: “I have a restaurant. Customers search the menu, order food and pick a table; I set the tables, opening hours and prices.”',
                action: Btn('Build my first app', icon: Icons.add, kind: BtnKind.primary, onPressed: () => s.apps.newJob()),
              ),
            );
          }
          return Column(children: [
            for (final a in list) ...[_appCard(context, s, a), const SizedBox(height: 12)],
          ]);
        },
      ),
    ]);
  }

  Widget _appCard(BuildContext context, AppState s, BuiltApp a) {
    final spec = a.spec;
    return Panel(
      child: Row(children: [
        LogoBox(accent: true, child: Text(a.name.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              const SizedBox(width: 8),
              _RunPill(run: s.apps.runOf(a.id)),
            ]),
            const SizedBox(height: 2),
            Muted(spec.summary.isEmpty ? a.request : spec.summary),
            const SizedBox(height: 2),
            Muted('http://localhost:${a.port} · ${spec.tables.length} tables · ${spec.pages.length} pages', mono: true, size: 11.5),
          ]),
        ),
        const SizedBox(width: 12),
        _RunControls(app: a),
        const SizedBox(width: 6),
        Btn('Open', small: true, onPressed: () => setState(() => openId = a.id)),
      ]),
    );
  }
}

class _RunPill extends StatelessWidget {
  const _RunPill({required this.run});
  final AppRun run;
  @override
  Widget build(BuildContext context) => switch (run) {
        AppRun.running => const Pill('Running', tone: Tone.green, lamp: LampState.on),
        AppRun.paused => const Pill('Paused', tone: Tone.amber, lamp: LampState.ring),
        AppRun.stopped => const Pill('Stopped', lamp: LampState.off),
      };
}

/// Run / Pause / Stop.
class _RunControls extends StatelessWidget {
  const _RunControls({required this.app});
  final BuiltApp app;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final run = s.apps.runOf(app.id);
    Future<void> act(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        s.toast('$e');
      }
    }

    return Wrap(spacing: 6, children: [
      if (run != AppRun.running)
        Btn(run == AppRun.paused ? 'Resume' : 'Run', icon: Icons.play_arrow_rounded, small: true, kind: BtnKind.green, onPressed: () => act(() => s.apps.start(app.id))),
      if (run == AppRun.running) Btn('Pause', icon: Icons.pause_rounded, small: true, onPressed: () => act(() => s.apps.pause(app.id))),
      if (run != AppRun.stopped) Btn('Stop', icon: Icons.stop_rounded, small: true, kind: BtnKind.ghost, onPressed: () => act(() => s.apps.stop(app.id))),
    ]);
  }
}

// ======================= the wizard =======================

class _Wizard extends StatefulWidget {
  const _Wizard({required this.job, required this.onOpen});
  final BuildJob job;
  final ValueChanged<int> onOpen;
  @override
  State<_Wizard> createState() => _WizardState();
}

class _WizardState extends State<_Wizard> {
  late final request = TextEditingController(text: widget.job.request);
  final change = TextEditingController();
  final answerCtrls = <String, TextEditingController>{};

  BuildJob get j => widget.job;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    const stages = ['describe', 'questions', 'plan', 'build'];
    final at = j.stage == 'done' ? 4 : stages.indexOf(j.stage);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead('Build an app', description: 'Step ${at < 4 ? at + 1 : 4} of 4 — the AI works one small piece at a time, so even a small model gets it right.', actions: [
        if (j.stage != 'build' || j.steps.every((st) => st.state != BuildState.working))
          Btn(j.stage == 'done' ? 'Close' : 'Cancel', kind: BtnKind.ghost, onPressed: s.apps.cancelJob),
      ]),
      _Steps(at: at),
      const SizedBox(height: 18),
      if (!s.llmReady)
        Panel(
          borderColor: LL.amber,
          child: Row(children: [
            const Icon(Icons.info_outline, color: LL.amber),
            const SizedBox(width: 12),
            const Expanded(child: Text('Choose an AI first (Settings → Models, or connect a cloud AI). It does the building.')),
            Btn('Open settings', small: true, onPressed: () => s.go(PageId.settings)),
          ]),
        )
      else
        switch (j.stage) {
          'describe' => _describe(s),
          'questions' => _questions(s),
          'plan' => _plan(s),
          _ => _build(s),
        },
      if (j.busy != null) ...[
        const SizedBox(height: 14),
        Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(j.busy!),
          const SizedBox(width: 8),
          Muted('(${s.llmLabel})'),
        ]),
      ],
      if (j.error != null && j.busy == null) ...[
        const SizedBox(height: 12),
        Text('The AI had trouble: ${j.error}  Try again, or say it more simply.', style: const TextStyle(color: LL.red, fontSize: 13)),
      ],
    ]);
  }

  // ---- 1. describe ----
  Widget _describe(AppState s) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What do you want?', style: displayStyle(context, 19)),
          const SizedBox(height: 4),
          const Muted('Say it in your own words: who uses it, what they can do, and what you, the manager, need to set.'),
          const SizedBox(height: 12),
          TextField(
            controller: request,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(hintText: 'I have a restaurant. Customers should search the menu, order food and choose a table…'),
            onChanged: (v) => setState(() => j.request = v),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            const Muted('Ideas:'),
            for (final (name, text) in _ideas)
              ActionChip(label: Text(name), onPressed: () => setState(() => request.text = j.request = text)),
          ]),
          const SizedBox(height: 20),
          Text('Pictures (optional)', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Muted('A screenshot of a website you like (your app will look like it), a photo of your menu or price list (used as real data), or your logo.'),
          const SizedBox(height: 10),
          _Pictures(job: j),
          const SizedBox(height: 20),
          Row(children: [
            const Spacer(),
            Btn('Next', icon: Icons.arrow_forward, kind: BtnKind.primary, onPressed: j.busy != null || request.text.trim().length < 10
                ? null
                : () => s.apps.askQuestions(j..request = request.text.trim())),
          ]),
        ]),
      );

  // ---- 2. questions + options ----
  Widget _questions(AppState s) {
    for (final q in j.questions) {
      answerCtrls[q] ??= TextEditingController(text: j.answers[q]);
    }
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(j.questions.isEmpty ? 'Almost there' : 'A few questions', style: displayStyle(context, 19)),
        const SizedBox(height: 4),
        Muted(j.questions.isEmpty ? 'Your description is clear. Choose what to make.' : 'Answer what you can; skip the rest.'),
        const SizedBox(height: 12),
        for (final q in j.questions) ...[
          Field(label: q, child: TextField(controller: answerCtrls[q], onChanged: (v) => j.answers[q] = v)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        const Eyebrow('What to make'),
        SwitchRow('A website for customers (and a manager page)', value: j.features.website, onChanged: (v) => setState(() => j.features = Features(website: v, ava: j.features.ava))),
        SwitchRow('Ava can use it in chats and on phone calls (MCP tools)', value: j.features.ava, onChanged: (v) => setState(() => j.features = Features(website: j.features.website, ava: v))),
        SwitchRow('Fill it with example data to start', value: j.exampleData, onChanged: (v) => setState(() => j.exampleData = v)),
        const SizedBox(height: 16),
        Row(children: [
          Btn('Back', kind: BtnKind.ghost, onPressed: () => setState(() => j.stage = 'describe')),
          const Spacer(),
          Btn('Make a plan', icon: Icons.arrow_forward, kind: BtnKind.primary, onPressed: j.busy != null ? null : () => s.apps.makePlan(j)),
        ]),
      ]),
    );
  }

  // ---- 3. plan ----
  Widget _plan(AppState s) {
    final p = j.plan!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.name, style: displayStyle(context, 21))),
            Btn('Rename', small: true, kind: BtnKind.ghost, onPressed: () async {
              final v = await _prompt(context, 'Name of the app', initial: p.name);
              if (v != null && v.isNotEmpty) s.apps.editPlan(j, p.copyWith(name: v));
            }),
          ]),
          if (p.summary.isNotEmpty) Muted(p.summary),
          const SizedBox(height: 4),
          const Muted('Check the plan. Nothing is built yet: change anything first.', size: 12),
        ]),
      ),
      const SizedBox(height: 12),
      Section(title: 'Data it keeps', children: [
        for (final (i, t) in p.tables.indexed)
          Tile(
            last: i == p.tables.length - 1,
            leading: Icon(t.single ? Icons.article_outlined : Icons.table_rows_outlined, size: 20),
            title: Text(t.title),
            subtitle: Muted([if (t.purpose.isNotEmpty) t.purpose, if (t.single) 'one record'].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _AccessPicker(value: t.access, onChanged: (a) => s.apps.editPlan(j, p.copyWith(tables: [for (final x in p.tables) x.id == t.id ? x.copyWith(access: a) : x]))),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => s.apps.editPlan(j, p.copyWith(tables: [for (final x in p.tables) if (x.id != t.id) x]))),
            ]),
          ),
      ]),
      if (p.features.website) ...[
        const SizedBox(height: 12),
        Section(title: 'Customer pages', trailing: const Muted('+ a manager page for everything'), children: [
          for (final (i, pg) in p.pages.indexed)
            Tile(
              last: i == p.pages.length - 1,
              leading: const Icon(Icons.web_outlined, size: 20),
              title: Text(pg.title),
              subtitle: Muted(pg.purpose),
              trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => s.apps.editPlan(j, p.copyWith(pages: [for (final x in p.pages) if (x.id != pg.id) x]))),
            ),
        ]),
      ],
      const SizedBox(height: 12),
      Panel(
        child: Row(children: [
          Expanded(child: TextField(controller: change, decoration: const InputDecoration(hintText: 'Change the plan, e.g. “add a table for staff shifts” or “customers book a table instead of ordering”'))),
          const SizedBox(width: 10),
          Btn('Change', onPressed: j.busy != null
              ? null
              : () async {
                  if (change.text.trim().isEmpty) return;
                  await s.apps.changePlan(j, change.text.trim());
                  if (j.error == null) change.clear();
                }),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Btn('Back', kind: BtnKind.ghost, onPressed: () => setState(() => j.stage = 'questions')),
        const Spacer(),
        Btn('Build it', icon: Icons.construction, kind: BtnKind.primary, large: true, onPressed: j.busy != null || p.tables.isEmpty ? null : () => s.apps.build(j)),
      ]),
    ]);
  }

  // ---- 4. build ----
  Widget _build(AppState s) {
    final failed = j.steps.any((st) => st.state == BuildState.failed);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Section(title: j.stage == 'done' ? 'Built' : 'Building, one piece at a time', children: [
        for (final (i, st) in j.steps.indexed)
          Tile(
            last: i == j.steps.length - 1,
            leading: SizedBox(
              width: 22,
              child: switch (st.state) {
                BuildState.working => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                BuildState.done => const Icon(Icons.check_circle, color: LL.green, size: 20),
                BuildState.simple => const Icon(Icons.check_circle_outline, color: LL.amber, size: 20),
                BuildState.skipped => Icon(Icons.remove_circle_outline, color: context.c.muted, size: 20),
                BuildState.failed => const Icon(Icons.error_outline, color: LL.red, size: 20),
                BuildState.waiting => Icon(Icons.radio_button_unchecked, color: context.c.muted, size: 20),
              },
            ),
            title: Text(st.title, style: TextStyle(fontWeight: st.state == BuildState.working ? FontWeight.w600 : FontWeight.w500)),
            subtitle: st.note == null ? null : Muted(st.note!),
          ),
      ]),
      if (failed) ...[
        const SizedBox(height: 12),
        Row(children: [const Spacer(), Btn('Try again', icon: Icons.refresh, kind: BtnKind.primary, onPressed: () => s.apps.retryFrom(j))]),
      ],
      if (j.stage == 'done' && j.appId != null) ...[
        const SizedBox(height: 16),
        Panel(
          borderColor: LL.green,
          child: Row(children: [
            const Icon(Icons.celebration_outlined, color: LL.green),
            const SizedBox(width: 12),
            const Expanded(child: Text('Your app is running. Open it, try it, and change any part of it.', style: TextStyle(fontWeight: FontWeight.w600))),
            FutureBuilder(
              future: s.apps.app(j.appId!),
              builder: (context, snap) => snap.data == null
                  ? const SizedBox()
                  : Btn('Open website', icon: Icons.open_in_new, small: true, onPressed: () => openExternal('http://localhost:${snap.data!.port}')),
            ),
            const SizedBox(width: 8),
            Btn('Manage it', kind: BtnKind.primary, small: true, onPressed: () {
              final id = j.appId!;
              s.apps.cancelJob();
              widget.onOpen(id);
            }),
          ]),
        ),
      ],
    ]);
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.at});
  final int at;
  @override
  Widget build(BuildContext context) {
    const names = ['Describe', 'Questions', 'Plan', 'Build'];
    return Row(children: [
      for (final (i, n) in names.indexed) ...[
        CircleAvatar(
          radius: 11,
          backgroundColor: i < at ? LL.green : (i == at ? LL.amber : context.c.line),
          child: i < at ? const Icon(Icons.check, size: 13, color: Colors.white) : Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
        ),
        const SizedBox(width: 6),
        Text(n, style: TextStyle(fontSize: 13, fontWeight: i == at ? FontWeight.w600 : FontWeight.w400, color: i <= at ? context.c.ink : context.c.muted)),
        if (i < names.length - 1) Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 10), color: context.c.line)),
      ],
    ]);
  }
}

class _AccessPicker extends StatelessWidget {
  const _AccessPicker({required this.value, required this.onChanged});
  final Access value;
  final ValueChanged<Access> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 200,
      child: Dropdown<String>(
        value: '${value.see}${value.add}',
        items: const {'falsefalse': 'Manager only', 'truefalse': 'Customers can see', 'falsetrue': 'Customers can add', 'truetrue': 'Customers see and add'},
        onChanged: (v) => onChanged(Access(see: v.startsWith('true'), add: v.endsWith('true'))),
      ));
}

// ======================= pictures =======================

/// Pictures for the AI to look at: picked from a file, or (on a Mac) a screenshot.
class _Pictures extends StatelessWidget {
  const _Pictures({required this.job});
  final BuildJob job;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final downloading = s.pulls.containsKey(_visionModel);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (i, (b64, notes)) in job.pictures.indexed)
          Container(
            width: 190,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: context.c.line), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(base64Decode(b64), height: 100, width: 174, fit: BoxFit.cover)),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    style: IconButton.styleFrom(backgroundColor: Colors.white70),
                    onPressed: () => s.apps.removePicture(job, i),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              notes == null ? const Muted('Looking…', size: 11.5) : Muted(_short(notes.summary, 140), size: 11.5),
            ]),
          ),
      ]),
      if (job.pictures.isNotEmpty) const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Btn('Add a picture', icon: Icons.image_outlined, small: true, onPressed: job.busy != null ? null : () => _add(context, s, () => _pickFile())),
        if (Platform.isMacOS) Btn('Take a screenshot', icon: Icons.screenshot_monitor_outlined, small: true, onPressed: job.busy != null ? null : () => _add(context, s, _screenshot)),
        if (downloading) Muted('Downloading $_visionModel so your AI can see pictures… ${s.pulls[_visionModel] == null ? '' : '${(s.pulls[_visionModel]! * 100).round()}%'}'),
      ]),
    ]);
  }

  static String _short(String t, int n) => t.length <= n ? t : '${t.substring(0, n)}…';

  Future<void> _add(BuildContext context, AppState s, Future<List<int>?> Function() get) async {
    final bytes = await get();
    if (bytes == null) return;
    final b64 = await _shrink(bytes);
    final err = await s.apps.addPicture(job, b64);
    if (err == 'novision' && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Let your AI see pictures', style: displayStyle(c, 20)),
          content: const SizedBox(
            width: 440,
            child: Text('None of your downloaded models can look at pictures. Download Gemma 3 (4B, about 3.3 GB)? '
                'It reads pictures here on this computer; your main AI stays the same.'),
          ),
          actions: [
            Btn('Not now', onPressed: () => Navigator.pop(c, false)),
            Btn('Download', kind: BtnKind.primary, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      );
      if (ok == true) {
        await s.pullModel(_visionModel, select: false);
        if (await s.visionModel() != null) await s.apps.addPicture(job, b64);
      }
    }
  }

  Future<List<int>?> _pickFile() async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Pictures', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'])]);
    return f?.readAsBytes();
  }

  /// macOS: drag over any part of the screen (e.g. a website in your browser).
  static Future<List<int>?> _screenshot() async {
    final path = '${Directory.systemTemp.path}/localailine-shot-${DateTime.now().millisecondsSinceEpoch}.png';
    await Process.run('screencapture', ['-i', '-x', path]);
    final f = File(path);
    if (!f.existsSync()) return null; // cancelled with Esc
    final bytes = await f.readAsBytes();
    await f.delete();
    return bytes;
  }
}

/// Big pictures are made smaller (at most 1280 px wide): faster for the AI, same meaning.
Future<String> _shrink(List<int> bytes) async {
  try {
    final buf = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    final desc = await ui.ImageDescriptor.encoded(buf);
    if (desc.width <= 1280) return base64Encode(bytes);
    final codec = await desc.instantiateCodec(targetWidth: 1280);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return png == null ? base64Encode(bytes) : base64Encode(png.buffer.asUint8List());
  } catch (_) {
    return base64Encode(bytes);
  }
}

// ======================= one app =======================

class _AppDetail extends StatefulWidget {
  const _AppDetail({required this.id, required this.onBack});
  final int id;
  final VoidCallback onBack;
  @override
  State<_AppDetail> createState() => _AppDetailState();
}

class _AppDetailState extends State<_AppDetail> {
  final add = TextEditingController();
  bool showPin = false;
  List<String> lan = [];

  @override
  void initState() {
    super.initState();
    HostServer.localAddresses().then((a) => mounted ? setState(() => lan = a) : null);
  }

  Future<void> _run(AppState s, Future<String?> Function() f) async {
    final err = await f();
    if (err != null) s.toast('The AI had trouble: $err');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FutureBuilder(
      future: Future.wait([s.apps.app(widget.id), s.apps.avaConnected(widget.id)]),
      builder: (context, snap) {
        final a = snap.data?[0] as BuiltApp?;
        if (a == null) return snap.hasData ? const Text('This app was deleted.') : const SizedBox();
        final ava = snap.data![1] as bool;
        final spec = a.spec;
        final run = s.apps.runOf(a.id);
        final busy = s.apps.editing[a.id];
        final local = 'http://localhost:${a.port}';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(tooltip: 'All apps', icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(a.name, style: displayStyle(context, 24))), const SizedBox(width: 10), _RunPill(run: run)]),
                if (spec.summary.isNotEmpty) Muted(spec.summary),
              ]),
            ),
            _RunControls(app: a),
          ]),
          const SizedBox(height: 16),
          if (busy != null) ...[
            Panel(
              borderColor: LL.amber,
              child: Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(busy)),
                Muted(s.llmLabel),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          Grid(cols: 2, children: [
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('Open it'),
                const SizedBox(height: 8),
                _link(context, 'Website', local, run == AppRun.stopped),
                _link(context, 'Manager page', '$local/manage', run == AppRun.stopped),
                for (final ip in lan) _link(context, 'On your Wi-Fi (phones)', 'http://$ip:${a.port}', run == AppRun.stopped),
                const SizedBox(height: 6),
                Row(children: [
                  Muted('Manager PIN: ', size: 13),
                  Mono(showPin ? a.pin : '••••••', size: 13),
                  IconButton(visualDensity: VisualDensity.compact, icon: Icon(showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16), onPressed: () => setState(() => showPin = !showPin)),
                  TextButton(onPressed: () async {
                    await s.apps.newPin(a.id);
                    s.toast('New manager PIN made. Sign in again on the manager page.');
                  }, child: const Text('New PIN')),
                ]),
                if (run == AppRun.stopped) const Muted('Run the app to open it.', size: 12),
              ]),
            ),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('Ava (chat and phone calls)'),
                const SizedBox(height: 4),
                SwitchRow('Ava can use this app', value: ava, onChanged: (v) => v ? s.apps.connectAva(a.id) : s.apps.disconnectAva(a.id)),
                const Muted('Callers can do what customers can (e.g. ask about the menu, place an order) — no approval needed. '
                    'You can also manage everything by chatting or talking to Ava; changes ask you first.', size: 12),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Section(title: 'Data', children: [
            for (final (i, t) in spec.tables.indexed)
              Tile(
                last: i == spec.tables.length - 1,
                leading: Icon(t.single ? Icons.article_outlined : Icons.table_rows_outlined, size: 20),
                title: Text(t.title),
                subtitle: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final f in t.fields) Pill('${f.label}${f.managerOnly ? ' · manager' : ''}', tone: f.link != null ? Tone.blue : Tone.neutral),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _AccessPicker(value: t.access, onChanged: (acc) => s.apps.setAccess(a.id, t.id, acc)),
                  const SizedBox(width: 6),
                  Btn('Change', small: true, onPressed: busy != null
                      ? null
                      : () async {
                          final v = await _prompt(context, 'Change “${t.title}”', hint: 'e.g. add a photo link and a “spicy” yes/no; remove “notes”');
                          if (v != null && v.isNotEmpty) await _run(s, () => s.apps.changeTable(a.id, t.id, v));
                        }),
                  IconButton(tooltip: 'Remove (deletes its data)', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () async {
                    if (await _confirm(context, 'Remove “${t.title}” and all its records?')) await s.apps.removePart(a.id, table: t.id);
                  }),
                ]),
              ),
          ]),
          if (spec.features.website || spec.pages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Section(title: 'Pages', trailing: const Muted('The manager page always shows all data'), children: [
              for (final (i, p) in spec.pages.indexed)
                Tile(
                  last: i == spec.pages.length - 1,
                  leading: const Icon(Icons.web_outlined, size: 20),
                  title: Text(p.title),
                  subtitle: Muted(p.blocks.map((b) => b.type == 'text' ? 'text' : '${b.type} of ${spec.table(b.table!)?.title.toLowerCase() ?? b.table}').join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (run != AppRun.stopped) Btn('View', small: true, kind: BtnKind.ghost, onPressed: () => openExternal('$local/p/${p.id}')),
                    Btn('Change', small: true, onPressed: busy != null
                        ? null
                        : () async {
                            final v = await _prompt(context, 'Change page “${p.title}”', hint: 'e.g. put the opening hours at the top; let people search the menu');
                            if (v != null && v.isNotEmpty) await _run(s, () => s.apps.changePage(a.id, p.id, v));
                          }),
                    IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () async {
                      if (await _confirm(context, 'Remove the page “${p.title}”?')) await s.apps.removePart(a.id, page: p.id);
                    }),
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Add something'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: add, decoration: const InputDecoration(hintText: 'e.g. a page where customers leave reviews; a table for staff shifts'))),
                const SizedBox(width: 10),
                Btn('Add', kind: BtnKind.primary, onPressed: busy != null
                    ? null
                    : () async {
                        final v = add.text.trim();
                        if (v.isEmpty) return;
                        add.clear();
                        await _run(s, () => s.apps.addPart(a.id, v));
                      }),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(color: _hex(spec.theme), borderRadius: BorderRadius.circular(6))),
              const SizedBox(width: 12),
              Expanded(child: Muted('Look: ${spec.dark ? 'dark' : 'light'}, ${spec.font} letters')),
              Btn('Change the look', small: true, onPressed: busy != null
                  ? null
                  : () async {
                      final v = await _prompt(context, 'Change the look', hint: 'e.g. dark with gold buttons; warm and friendly');
                      if (v != null && v.isNotEmpty) await _run(s, () => s.apps.changeLook(a.id, v));
                    }),
              const SizedBox(width: 6),
              Btn('Like a picture…', small: true, icon: Icons.image_outlined, onPressed: busy != null
                  ? null
                  : () async {
                      final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Pictures', extensions: ['png', 'jpg', 'jpeg', 'webp'])]);
                      if (f == null) return;
                      final b64 = await _shrink(await f.readAsBytes());
                      await _run(s, () => s.apps.changeLook(a.id, '', pictureBase64: b64));
                    }),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Muted('Your request: “${a.request.length > 140 ? '${a.request.substring(0, 140)}…' : a.request}”', size: 12),
            const Spacer(),
            Btn('Delete app', kind: BtnKind.danger, small: true, onPressed: () async {
              if (!await _confirm(context, 'Delete ${a.name} and all its data? This can’t be undone.')) return;
              await s.apps.delete(a.id);
              widget.onBack();
            }),
          ]),
        ]);
      },
    );
  }

  Widget _link(BuildContext context, String label, String url, bool off) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 160, child: Muted(label, size: 13)),
          Expanded(child: Mono(url, size: 12.5)),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Copy', icon: const Icon(Icons.copy, size: 15), onPressed: () => Clipboard.setData(ClipboardData(text: url))),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Open', icon: const Icon(Icons.open_in_new, size: 15), onPressed: off ? null : () => openExternal(url)),
        ]),
      );
}

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

Future<String?> _prompt(BuildContext context, String title, {String initial = '', String? hint}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title, style: displayStyle(d, 20)),
      content: SizedBox(
        width: 480,
        child: TextField(controller: c, autofocus: true, minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(d, v.trim())),
      ),
      actions: [
        Btn('Cancel', onPressed: () => Navigator.pop(d)),
        Btn('OK', kind: BtnKind.primary, onPressed: () => Navigator.pop(d, c.text.trim())),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String q) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(q),
        actions: [Btn('Cancel', onPressed: () => Navigator.pop(d, false)), Btn('Yes', kind: BtnKind.danger, onPressed: () => Navigator.pop(d, true))],
      ),
    ) ??
    false;
