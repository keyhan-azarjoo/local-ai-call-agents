import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/apps/app_spec.dart';
import '../../services/apps/app_styles.dart';
import '../../services/apps/app_templates.dart';
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead('Build an app',
          description: 'A website for your customers, a manager page for you, and tools Ava can use on calls — running on this computer. '
              'Start from a ready-made app, or describe your own and your AI builds it step by step.',
          actions: [Btn('Describe my own', icon: Icons.auto_fix_high_outlined, kind: BtnKind.primary, onPressed: () => s.apps.newJob())]),
      FutureBuilder(
        future: s.apps.apps(),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (list.isEmpty) return const SizedBox();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your apps', style: displayStyle(context, 18)),
            const SizedBox(height: 10),
            for (final a in list) ...[_appCard(context, s, a), const SizedBox(height: 12)],
            const SizedBox(height: 18),
          ]);
        },
      ),
      Text('Start from a ready-made app', style: displayStyle(context, 18)),
      const SizedBox(height: 4),
      const Muted('Complete with pages, a manager dashboard, example data and photos. Change anything afterwards — by hand or by telling the AI.'),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 1000 ? 4 : (box.maxWidth > 700 ? 3 : 2);
        return Wrap(spacing: 14, runSpacing: 14, children: [
          _DescribeCard(width: (box.maxWidth - 14 * (cols - 1)) / cols, onTap: () => s.apps.newJob()),
          for (final t in appTemplates)
            _TemplateCard(t: t, width: (box.maxWidth - 14 * (cols - 1)) / cols, busy: creating == t.id, onUse: creating != null ? null : () => _use(s, t)),
        ]);
      }),
    ]);
  }

  String? creating;

  Future<void> _use(AppState s, AppTemplate t) async {
    final d = await _askBusiness(context, t);
    if (d == null) return;
    setState(() => creating = t.id);
    try {
      final id = await s.apps.createFromTemplate(t, name: d.name, phone: d.phone, address: d.address);
      if (mounted) setState(() => openId = id);
      s.toast('${d.name.isEmpty ? t.name : d.name} is ready and running.');
    } catch (e) {
      s.toast('Could not create it: $e');
    } finally {
      if (mounted) setState(() => creating = null);
    }
  }

  Widget _appCard(BuildContext context, AppState s, BuiltApp a) {
    final spec = a.spec;
    final st = styleOf(spec.style);
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        _StyleSwatch(style: st, accent: spec.theme, letter: a.name.characters.first.toUpperCase(), size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5))),
              const SizedBox(width: 8),
              _RunPill(run: s.apps.runOf(a.id)),
            ]),
            const SizedBox(height: 2),
            Muted(spec.site['tagline'] ?? (spec.summary.isEmpty ? a.request : spec.summary)),
            const SizedBox(height: 2),
            Muted('localhost:${a.port} · ${st.name} style · ${spec.tables.length} tables · ${spec.pages.length} pages', mono: true, size: 11.5),
          ]),
        ),
        const SizedBox(width: 12),
        if (s.apps.runOf(a.id) != AppRun.stopped) ...[
          Btn('Website', small: true, kind: BtnKind.ghost, icon: Icons.open_in_new, onPressed: () => openExternal('http://localhost:${a.port}')),
          const SizedBox(width: 6),
        ],
        _RunControls(app: a),
        const SizedBox(width: 6),
        Btn('Open', small: true, kind: BtnKind.primary, onPressed: () => setState(() => openId = a.id)),
        IconButton(tooltip: 'Delete this app', icon: const Icon(Icons.delete_outline, size: 19), onPressed: () => _deleteApp(context, s, a)),
      ]),
    );
  }
}

const _templateIcons = <String, IconData>{
  'restaurant': Icons.restaurant_outlined,
  'salon': Icons.content_cut,
  'gym': Icons.fitness_center,
  'shop': Icons.storefront_outlined,
  'clinic': Icons.medical_services_outlined,
  'hotel': Icons.hotel_outlined,
  'garage': Icons.car_repair,
  'tutoring': Icons.school_outlined,
  'events': Icons.confirmation_number_outlined,
  'realestate': Icons.home_work_outlined,
};

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

/// A small preview of a website style: its background, colour and letters.
class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style, this.accent = '', this.letter, this.size = 48});
  final SiteStyle style;
  final String accent;
  final String? letter;
  final double size;
  @override
  Widget build(BuildContext context) {
    final a = _hex(accent.isEmpty ? style.accent : accent);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _hex(style.bg), borderRadius: BorderRadius.circular(12), border: Border.all(color: _hex(style.line))),
      alignment: Alignment.center,
      child: Container(
        width: size * .56,
        height: size * .56,
        decoration: BoxDecoration(color: a, borderRadius: BorderRadius.circular(style.radius > 10 ? 10 : style.radius.toDouble())),
        alignment: Alignment.center,
        child: Text(letter ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * .26, color: _hex(SiteStyle.onColor(accent.isEmpty ? style.accent : accent)))),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.t, required this.width, required this.busy, required this.onUse});
  final AppTemplate t;
  final double width;
  final bool busy;
  final VoidCallback? onUse;
  @override
  Widget build(BuildContext context) {
    final st = styleOf((t.spec['site'] as Map?)?['style'] as String?);
    final name = t.spec['name'] as String;
    return SizedBox(
      width: width,
      child: Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // A tiny picture of the website in its style.
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: _hex(st.bg),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(LL.r)),
              border: Border(bottom: BorderSide(color: context.c.line)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: _hex(st.accent), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _hex(st.ink)))),
                Icon(_templateIcons[t.id] ?? Icons.apps, size: 18, color: _hex(st.muted)),
              ]),
              const Spacer(),
              Text((t.spec['site'] as Map?)?['tagline'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, height: 1.15, fontWeight: FontWeight.w700, color: _hex(st.ink), fontFamily: st.headFont.contains('serif') && !st.headFont.contains('sans') ? 'serif' : null)),
              const SizedBox(height: 8),
              Container(width: 54, height: 8, decoration: BoxDecoration(color: _hex(st.accent), borderRadius: BorderRadius.circular(99))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 3),
              SizedBox(height: 36, child: Muted(t.blurb, size: 12.5)),
              const SizedBox(height: 10),
              Row(children: [
                Pill(st.name),
                const Spacer(),
                busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Btn('Use this', small: true, kind: BtnKind.primary, onPressed: onUse),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DescribeCard extends StatelessWidget {
  const _DescribeCard({required this.width, required this.onTap});
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 246,
        child: Material(
          color: LL.navy,
          borderRadius: BorderRadius.circular(LL.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(LL.r),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: LL.amber, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.auto_fix_high, color: LL.navy),
                ),
                const Spacer(),
                const Text('Describe your own', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: LL.display)),
                const SizedBox(height: 6),
                const Text('Tell the AI what you need, add a picture of a website you like, and it builds it step by step.',
                    style: TextStyle(color: LL.navText, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 12),
                const Row(children: [Text('Start', style: TextStyle(color: LL.amber, fontWeight: FontWeight.w600)), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 16, color: LL.amber)]),
              ]),
            ),
          ),
        ),
      );
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
  late final business = TextEditingController(text: widget.job.businessName);
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
          Field(
            label: 'Name of your business',
            child: TextField(controller: business, decoration: const InputDecoration(hintText: 'e.g. Trattoria Bella'), onChanged: (v) => j.businessName = v.trim()),
          ),
          const SizedBox(height: 18),
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
        if (j.features.website) ...[
          const SizedBox(height: 14),
          const Eyebrow('Website style'),
          const SizedBox(height: 4),
          const Muted('You can change it any time. A website picture you added decides the colours.', size: 12),
          const SizedBox(height: 10),
          _StylePicker(value: j.style ?? suggestStyle(j.request), onChanged: (v) => setState(() => j.style = v)),
        ],
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

/// The website styles, each with what it looks like and what it suits.
class _StylePicker extends StatelessWidget {
  const _StylePicker({required this.value, required this.onChanged, this.accent = ''});
  final String value, accent;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 900 ? 3 : 2;
        final w = (box.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final st in siteStyles)
            SizedBox(
              width: w,
              child: Material(
                color: context.c.panel,
                borderRadius: BorderRadius.circular(LL.r),
                child: InkWell(
                  borderRadius: BorderRadius.circular(LL.r),
                  onTap: () => onChanged(st.id),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(LL.r),
                      border: Border.all(color: value == st.id ? LL.amber : context.c.line, width: value == st.id ? 2 : 1),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _StyleSwatch(style: st, accent: value == st.id ? accent : '', letter: 'Aa', size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            if (value == st.id) const Icon(Icons.check_circle, size: 18, color: LL.amber),
                          ]),
                          const SizedBox(height: 2),
                          Muted(st.about, size: 12),
                          const SizedBox(height: 4),
                          Muted('Good for: ${st.goodFor}', size: 11.5),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      });
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
            if (run != AppRun.stopped) ...[
              Btn('Website', small: true, kind: BtnKind.ghost, icon: Icons.open_in_new, onPressed: () => openExternal(local)),
              const SizedBox(width: 6),
              Btn('Edit texts & photos', small: true, kind: BtnKind.ghost, icon: Icons.edit_outlined, onPressed: () => openExternal('$local/manage#website')),
              const SizedBox(width: 6),
            ],
            _RunControls(app: a),
            IconButton(tooltip: 'Delete this app', icon: const Icon(Icons.delete_outline), onPressed: () async {
              if (await _deleteApp(context, s, a)) widget.onBack();
            }),
          ]),
          const SizedBox(height: 16),
          _ChangeBox(app: a, busy: busy != null, onRun: (f) => _run(s, f)),
          const SizedBox(height: 14),
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
          if (spec.features.website || spec.pages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Eyebrow('Website style')),
                  if (spec.theme.isNotEmpty) TextButton(onPressed: () => s.apps.setStyle(a.id, spec.style), child: const Text('Use the style’s own colour')),
                ]),
                const SizedBox(height: 10),
                _StylePicker(value: spec.style, accent: spec.theme, onChanged: (v) => s.apps.setStyle(a.id, v)),
                const SizedBox(height: 10),
                const Muted('Texts, logo, cover photo, contact details and colour can also be edited on the manager page → Design & texts.', size: 12),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Muted('Your request: “${a.request.length > 140 ? '${a.request.substring(0, 140)}…' : a.request}”', size: 12),
            const Spacer(),
            Btn('Delete app', kind: BtnKind.danger, small: true, icon: Icons.delete_forever_outlined, onPressed: () async {
              if (await _deleteApp(context, s, a)) widget.onBack();
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

/// "Describe a change": one sentence about anything; the AI finds the part and changes only that.
class _ChangeBox extends StatefulWidget {
  const _ChangeBox({required this.app, required this.busy, required this.onRun});
  final BuiltApp app;
  final bool busy;
  final Future<void> Function(Future<String?> Function()) onRun;
  @override
  State<_ChangeBox> createState() => _ChangeBoxState();
}

class _ChangeBoxState extends State<_ChangeBox> {
  final ctrl = TextEditingController();
  static const _examples = [
    'Make it dark and luxurious',
    'Add a page with our story and photos',
    'Orders need a phone number',
    'Add allergens to the menu',
    'Change the slogan to “Fresh every day”',
  ];

  Future<void> _go(AppState s) async {
    final v = ctrl.text.trim();
    if (v.isEmpty) return;
    await widget.onRun(() => s.apps.changeAnything(widget.app.id, v));
    if (mounted) ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Panel(
      borderColor: LL.amber.withValues(alpha: .6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_fix_high, size: 20, color: LL.amber),
          const SizedBox(width: 8),
          Text('Change it by describing', style: displayStyle(context, 17)),
        ]),
        const SizedBox(height: 4),
        const Muted('Say what you want different — the look, a page, the data, or something new. The AI changes only that part; your data stays.'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 4,
              enabled: !widget.busy,
              decoration: const InputDecoration(hintText: 'e.g. “Add a gallery page”, “make the buttons green”, “customers can choose pickup or delivery”'),
              onSubmitted: (_) => _go(s),
            ),
          ),
          const SizedBox(width: 10),
          Btn('Make the change', kind: BtnKind.primary, icon: Icons.arrow_forward, onPressed: widget.busy ? null : () => _go(s)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final e in _examples) ActionChip(label: Text(e, style: const TextStyle(fontSize: 12)), onPressed: widget.busy ? null : () => setState(() => ctrl.text = e)),
          ActionChip(
            avatar: const Icon(Icons.image_outlined, size: 16),
            label: const Text('Look like a picture…', style: TextStyle(fontSize: 12)),
            onPressed: widget.busy
                ? null
                : () async {
                    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Pictures', extensions: ['png', 'jpg', 'jpeg', 'webp'])]);
                    if (f == null) return;
                    final b64 = await _shrink(await f.readAsBytes());
                    await widget.onRun(() => s.apps.changeLook(widget.app.id, ctrl.text.trim(), pictureBase64: b64));
                  },
          ),
        ]),
      ]),
    );
  }
}

/// Your business's name and contact details, put into a ready-made app.
Future<({String name, String phone, String address})?> _askBusiness(BuildContext context, AppTemplate t) {
  final site = (t.spec['site'] as Map?) ?? const {};
  final name = TextEditingController(), phone = TextEditingController(), address = TextEditingController();
  String? error;
  return showDialog(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text('About your business', style: displayStyle(d, 20)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Muted('Your ${t.name.toLowerCase()} app will use these everywhere — the website, the manager page and Ava. You can change them later.'),
            const SizedBox(height: 14),
            Field(label: 'Name of your business', child: TextField(controller: name, autofocus: true, decoration: InputDecoration(hintText: 'e.g. ${t.spec['name']}'))),
            const SizedBox(height: 10),
            Field(label: 'Phone (optional)', child: TextField(controller: phone, decoration: InputDecoration(hintText: '${site['phone'] ?? ''}'))),
            const SizedBox(height: 10),
            Field(label: 'Address (optional)', child: TextField(controller: address, decoration: InputDecoration(hintText: '${site['address'] ?? ''}'))),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: LL.red, fontSize: 13))),
          ]),
        ),
        actions: [
          Btn('Cancel', onPressed: () => Navigator.pop(d)),
          Btn('Create my app', kind: BtnKind.primary, onPressed: () {
            if (name.text.trim().isEmpty) return set(() => error = 'Type the name of your business.');
            Navigator.pop(d, (name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim()));
          }),
        ],
      ),
    ),
  );
}

/// Asks clearly, then deletes the app and everything that belongs to it.
Future<bool> _deleteApp(BuildContext context, AppState s, BuiltApp a) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Delete ${a.name}?', style: displayStyle(d, 20)),
      content: const SizedBox(
        width: 440,
        child: Text('This removes it completely: the website and manager page, all its records (orders, bookings…), '
            'its uploaded pictures, and Ava’s tools for it. This can’t be undone.'),
      ),
      actions: [
        Btn('Cancel', onPressed: () => Navigator.pop(d, false)),
        Btn('Delete for good', kind: BtnKind.danger, icon: Icons.delete_forever_outlined, onPressed: () => Navigator.pop(d, true)),
      ],
    ),
  );
  if (ok != true) return false;
  await s.apps.delete(a.id);
  s.toast('${a.name} was deleted.');
  return true;
}

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
