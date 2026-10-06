import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/abilities.dart';
import '../../services/agent_templates.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'live_talk.dart' show voiceOptions;

/// The call flow: who answers, who calls can be passed to (AI agents or real people), drawn as
/// cards you can drag and link. A call starts with the agent that answers; any agent can pass it
/// along a link, with a short brief, and the next one carries on in their own voice.
class CallFlowPage extends StatefulWidget {
  const CallFlowPage({super.key});
  @override
  State<CallFlowPage> createState() => _CallFlowPageState();
}

const _cardW = 230.0, _cardH = 118.0;

class _CallFlowPageState extends State<CallFlowPage> {
  List<Map<String, Object?>> agents = [];
  List<Map<String, Object?>> lines = [];
  int? lineFrom; // dragging a link from a phone line
  Map<String, Offset> pos = {};
  int? linkFrom; // dragging a new link from this agent
  Offset? linkEnd;
  int? setMax; // null: the suggestion for this computer

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final rows = await s.db.all('agents', where: "handles IN ('incoming', 'handoff', 'human')", orderBy: 'id');
    final layout = (jsonDecode(await s.db.setting('flow.layout') ?? '{}') as Map).cast<String, dynamic>();
    final mc = int.tryParse(await s.db.setting('calls.max') ?? '');
    final ls = await s.db.all('lines', orderBy: 'id');
    if (!mounted) return;
    setState(() {
      agents = rows;
      lines = ls;
      setMax = mc;
      pos = {for (final e in layout.entries) e.key: Offset((e.value[0] as num).toDouble(), (e.value[1] as num).toDouble())};
      // New cards: the answering agent on the left, the rest in a column to the right.
      var i = 0;
      for (final a in rows) {
        final k = '${a['id']}';
        if (pos.containsKey(k)) continue;
        pos[k] = a['handles'] == 'incoming' ? const Offset(270, 160) : Offset(600 + (i ~/ 4) * 300, 20 + (i % 4) * 150.0);
        if (a['handles'] != 'incoming') i++;
      }
    });
  }

  Future<void> _saveLayout() async {
    await context.read<AppState>().db.setSetting('flow.layout', jsonEncode({for (final e in pos.entries) e.key: [e.value.dx.round(), e.value.dy.round()]}));
  }

  Map<String, dynamic> _access(Map<String, Object?> a) {
    try {
      return (jsonDecode('${a['access'] ?? '{}'}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  /// The links drawn from an agent (null = none drawn yet: it can pass to everyone with a "when").
  Set<int> _links(Map<String, Object?> a) {
    final l = _access(a)['passTo'];
    if (l is List) return {for (final v in l) (v as num).toInt()};
    return {
      for (final b in agents)
        if (b['id'] != a['id'] && a['handles'] != 'human' && ('${b['transfer_when'] ?? ''}'.trim().isNotEmpty || b['handles'] == 'incoming')) b['id'] as int,
    };
  }

  Future<void> _setLinks(Map<String, Object?> a, Set<int> links) async {
    final s = context.read<AppState>();
    final acc = _access(a)..['passTo'] = links.toList();
    await s.db.update('agents', a['id'] as int, {'access': jsonEncode(acc)});
    await _load();
  }

  int? _lineAgent(Map<String, Object?> line) {
    try {
      return ((jsonDecode('${line['config'] ?? '{}'}') as Map)['agentId'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _setLineAgent(Map<String, Object?> line, int agentId) async {
    final s = context.read<AppState>();
    final cfg = (jsonDecode('${line['config'] ?? '{}'}') as Map).cast<String, dynamic>()..['agentId'] = agentId;
    await s.db.update('lines', line['id'] as int, {'config': jsonEncode(cfg)});
    await s.log('Calls to ${line['number']} now answered by ${agents.firstWhere((a) => a['id'] == agentId)['name']}');
    await _load();
  }

  /// A phone line: drag its dot to the agent that should answer calls on it.
  Widget _lineCard(int i, Offset o) {
    final l = lines[i];
    return Positioned(
      left: o.dx,
      top: o.dy,
      child: Container(
        width: 170,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: LL.navy, borderRadius: BorderRadius.circular(LL.r)),
        child: Stack(clipBehavior: Clip.none, children: [
          Row(children: [
            const Icon(Icons.call, color: LL.amber, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l['number'] ?? l['label']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5), overflow: TextOverflow.ellipsis),
                Text('${l['label']}', style: const TextStyle(color: LL.navText, fontSize: 11), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          Positioned(right: -22, top: 26 - 22, child: _dot(onStart: () => setState(() {
                lineFrom = i;
                linkEnd = o + const Offset(170, 26);
              }), onEnd: () async {
                final to = linkEnd == null ? null : _at(linkEnd!);
                setState(() {
                  lineFrom = null;
                  linkEnd = null;
                });
                if (to != null && to['handles'] != 'human') await _setLineAgent(l, to['id'] as int);
              })),
        ]),
      ),
    );
  }

  /// A big, easy-to-grab dot to drag a link from.
  Widget _dot({required VoidCallback onStart, required Future<void> Function() onEnd}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onStart(),
        onPanUpdate: (d) => setState(() => linkEnd = (linkEnd ?? Offset.zero) + d.delta),
        onPanEnd: (_) => onEnd(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Tooltip(
              message: 'Drag to connect',
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: LL.amber, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                child: const Icon(Icons.add, size: 12, color: LL.navy),
              ),
            ),
          ),
        ),
      );

  Map<String, Object?>? _at(Offset p) {
    for (final a in agents.reversed) {
      final o = pos['${a['id']}']!;
      if (Rect.fromLTWH(o.dx, o.dy, _cardW, _cardH).contains(p)) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final maxCalls = setMax ?? s.defaultMaxCalls;
    final entry = agents.where((a) => a['handles'] == 'incoming').firstOrNull;
    final edges = <(Offset, Offset, int, int)>[];
    for (final a in agents) {
      for (final to in _links(a)) {
        final pa = pos['${a['id']}'], pb = pos['$to'];
        if (pa == null || pb == null) continue;
        // Links going back left leave from the card's left side and arrive at the right side.
        final back = pb.dx + _cardW / 2 < pa.dx;
        edges.add(back
            ? (pa + const Offset(0, _cardH / 2 + 12), pb + const Offset(_cardW, _cardH / 2 + 12), a['id'] as int, to)
            : (pa + const Offset(_cardW, _cardH / 2), pb + const Offset(0, _cardH / 2), a['id'] as int, to));
      }
    }
    final start = const Offset(20, 185);
    // Phone lines down the left; each one links to the agent that answers it.
    Offset linePos(int i) => Offset(20, 40 + i * 110.0);
    final lineEdges = <(Offset, Offset)>[];
    for (var i = 0; i < lines.length; i++) {
      final to = _lineAgent(lines[i]) ?? entry?['id'];
      final pb = to == null ? null : pos['$to'];
      if (pb != null) lineEdges.add((linePos(i) + const Offset(170, 26), pb + const Offset(0, _cardH / 2)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Call flow',
          description: 'Who answers each line, and who a call can be passed to. Drag a card to move it. Drag from an orange + dot onto another card to connect them. Tap a line between cards to remove it.',
          actions: [
            Btn('Set up a team', icon: Icons.auto_awesome, kind: BtnKind.amber, onPressed: _setupTeam),
            Btn('Add AI agent', icon: Icons.smart_toy_outlined, onPressed: _pickRole),
            Btn('Add person', icon: Icons.person_add_alt, kind: BtnKind.primary, onPressed: () => _add(human: true)),
          ]),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          const Icon(Icons.call_split, size: 18),
          const SizedBox(width: 10),
          const Expanded(child: Text('Calls at the same time', style: TextStyle(fontWeight: FontWeight.w600))),
          Muted('${s.activeCalls} now · suggested ${s.defaultMaxCalls} for this computer  ', size: 12),
          IconButton(icon: const Icon(Icons.remove), onPressed: maxCalls <= 1 ? null : () => _setMax(maxCalls - 1)),
          Text('$maxCalls', style: displayStyle(context, 18)),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _setMax(maxCalls + 1)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        height: 640,
        decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(LL.r), border: Border.all(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: max(1300, (pos.values.fold<double>(0, (m, o) => max(m, o.dx)) + _cardW + 60)),
            height: 640,
            child: GestureDetector(
              onTapUp: (d) => _tapEdge(d.localPosition, edges),
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Edges(
                      edges: edges,
                      start: start,
                      entry: lines.isEmpty && entry != null ? pos['${entry['id']}'] : null,
                      lineEdges: lineEdges,
                      color: LL.amber,
                      line: c.muted,
                      linkFrom: lineFrom != null ? linePos(lineFrom!) + const Offset(170, 26) : (linkFrom == null ? null : pos['$linkFrom']! + const Offset(_cardW, _cardH / 2)),
                      linkEnd: linkEnd,
                    ),
                  ),
                ),
                if (lines.isEmpty) Positioned(left: start.dx, top: start.dy - 22, child: const _Start()),
                for (var i = 0; i < lines.length; i++) _lineCard(i, linePos(i)),
                for (final a in agents) _card(a),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Muted('Each agent only uses the tools, skills and documents you give it (tap a card), so it stays fast and focused. People are rung on their phone; the agent briefs them, then leaves the call to them.'),
    ]);
  }

  Widget _card(Map<String, Object?> a) {
    final c = context.c;
    final k = '${a['id']}';
    final o = pos[k]!;
    final human = a['handles'] == 'human';
    final entry = a['handles'] == 'incoming';
    final acc = _access(a);
    String count(String key, String noun) => acc[key] is List ? '${(acc[key] as List).length} $noun${(acc[key] as List).length == 1 ? '' : 's'}' : 'all $noun' 's';
    return Positioned(
      left: o.dx,
      top: o.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => pos[k] = Offset(max(0, o.dx + d.delta.dx), max(0, o.dy + d.delta.dy).toDouble())),
        onPanEnd: (_) => _saveLayout(),
        onTap: () => _edit(a),
        child: Container(
          width: _cardW,
          height: _cardH,
          padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(LL.r),
            border: Border.all(color: entry ? LL.amber : c.line, width: entry ? 2 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(human ? Icons.person_outline : Icons.smart_toy_outlined, size: 18, color: human ? LL.green : LL.amber),
                const SizedBox(width: 6),
                Expanded(child: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                if (a['enabled'] != 1) const Pill('Off'),
              ]),
              const SizedBox(height: 4),
              Text(
                entry ? 'Answers every call' : (('${a['transfer_when'] ?? ''}').trim().isEmpty ? 'Tap to say when calls come here' : 'When: ${a['transfer_when']}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const Spacer(),
              Muted(
                human
                    ? [if (acc['device'] != null) 'Rings their app', if ('${acc['number'] ?? ''}'.isNotEmpty) 'Rings ${acc['number']}'].join(' · ').ifEmpty('Add a number or paired phone')
                    : [
                        ...[for (final ab in (acc['abilities'] is List ? acc['abilities'] as List : (entry ? ['message'] : const []))) Abilities.labels[ab]?.split(' ').skip(1).join(' ')].nonNulls,
                        count('tools', 'system'),
                      ].join(' · '),
                size: 11,
              ),
            ]),
            if (!human)
              Positioned(
                right: -40,
                top: _cardH / 2 - 22,
                child: _dot(
                  onStart: () => setState(() {
                    linkFrom = a['id'] as int;
                    linkEnd = o + const Offset(_cardW, _cardH / 2);
                  }),
                  onEnd: () async {
                    final to = linkEnd == null ? null : _at(linkEnd!);
                    setState(() {
                      linkFrom = null;
                      linkEnd = null;
                    });
                    if (to != null && to['id'] != a['id']) await _setLinks(a, {..._links(a), to['id'] as int});
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Tapping close to a link removes it.
  Future<void> _tapEdge(Offset p, List<(Offset, Offset, int, int)> edges) async {
    for (final e in edges) {
      for (var t = 0.0; t <= 1; t += 0.02) {
        if ((_Edges.at(e.$1, e.$2, t) - p).distance < 8) {
          final from = agents.firstWhere((a) => a['id'] == e.$3);
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Remove this link?'),
              content: Text('${from['name']} won’t pass calls to ${agents.firstWhere((a) => a['id'] == e.$4)['name']} any more.'),
              actions: [Btn('Keep', onPressed: () => Navigator.pop(c, false)), Btn('Remove', kind: BtnKind.danger, onPressed: () => Navigator.pop(c, true))],
            ),
          );
          if (ok == true) await _setLinks(from, _links(from)..remove(e.$4));
          return;
        }
      }
    }
  }

  Future<void> _setMax(int n) async {
    await context.read<AppState>().setMaxCalls(n);
    setState(() => setMax = n);
  }

  Future<int> _create(RoleTemplate t) => context.read<AppState>().addRole(t);

  Future<void> _add({required bool human}) async {
    final id = await _create(human
        ? const RoleTemplate('Manager', 'Person', 'The caller asks for a person or a manager.', '', person: true)
        : const RoleTemplate('New agent', 'Specialist', '', 'Be brief, warm and accurate.'));
    await _load();
    final a = agents.firstWhere((a) => a['id'] == id);
    if (mounted) await _edit(a);
  }

  /// Add one agent from a ready-made role (or a blank one).
  Future<void> _pickRole() async {
    final roles = <RoleTemplate>[
      ...extraRoles,
      for (final b in businessTemplates)
        for (final r in b.roles)
          if (!r.answers && !r.person) r,
    ];
    final picked = await showDialog<RoleTemplate?>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Add an AI agent'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, const RoleTemplate('New agent', 'Specialist', '', 'Be brief, warm and accurate.')), child: const Text('Blank agent — I’ll write its job')),
          const Divider(),
          for (final r in roles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, r),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.role} · ${r.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Muted(r.when, size: 12),
              ]),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final id = await _create(picked);
    await _load();
    final a = agents.firstWhere((a) => a['id'] == id);
    if (mounted) await _edit(a);
  }

  /// A whole team for a kind of business: receptionist, specialists and a person, already linked.
  Future<void> _setupTeam() async {
    final s = context.read<AppState>();
    final b = await showDialog<BusinessTemplate?>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('What kind of business?'),
        children: [
          for (final b in businessTemplates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, b),
              child: Row(children: [
                Text(b.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Muted(b.roles.map((r) => r.role).join(' · '), size: 12),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    );
    if (b == null) return;
    await s.setUpTeam(b);
    await _load();
    s.toast('Team added. Tap a card to adjust it; add phone numbers for the people.');
  }

  Future<void> _edit(Map<String, Object?> a) async {
    await showDialog(context: context, builder: (_) => _AgentEditor(agent: a));
    await _load();
  }
}

class _Start extends StatelessWidget {
  const _Start();
  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: LL.navy, borderRadius: BorderRadius.circular(LL.r)),
        child: const Row(children: [
          Icon(Icons.call, color: LL.amber, size: 18),
          SizedBox(width: 8),
          Text('A call comes in', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}

class _Edges extends CustomPainter {
  _Edges({required this.edges, required this.start, required this.entry, required this.color, required this.line, this.linkFrom, this.linkEnd, this.lineEdges = const []});
  final List<(Offset, Offset, int, int)> edges;
  final List<(Offset, Offset)> lineEdges;
  final Offset start;
  final Offset? entry, linkFrom, linkEnd;
  final Color color, line;

  static Offset at(Offset a, Offset b, double t) {
    final dir = b.dx >= a.dx ? 1.0 : -1.0;
    final k = max(60.0, (b.dx - a.dx).abs() / 2);
    final c1 = Offset(a.dx + dir * k, a.dy), c2 = Offset(b.dx - dir * k, b.dy);
    final u = 1 - t;
    return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t);
  }

  void _curve(Canvas canvas, Offset a, Offset b, Paint paint) {
    final path = Path()..moveTo(a.dx, a.dy);
    for (var t = 0.02; t <= 1.001; t += 0.02) {
      final p = at(a, b, t);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
    // Arrow head.
    final d = b - at(a, b, 0.95);
    final ang = atan2(d.dy, d.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(b.dx - 10 * cos(ang - 0.4), b.dy - 10 * sin(ang - 0.4))
      ..lineTo(b.dx - 10 * cos(ang + 0.4), b.dy - 10 * sin(ang + 0.4))
      ..close();
    canvas.drawPath(head, Paint()..color = paint.color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line.withValues(alpha: .7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (entry != null) _curve(canvas, start + const Offset(150, 0), entry! + const Offset(0, _cardH / 2), Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke);
    for (final e in lineEdges) {
      _curve(canvas, e.$1, e.$2, Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke);
    }
    for (final e in edges) {
      _curve(canvas, e.$1, e.$2, p);
    }
    if (linkFrom != null && linkEnd != null) _curve(canvas, linkFrom!, linkEnd!, Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_Edges old) => true;
}

/// Edit one agent or person: name, voice, when calls come to them, what they may use.
class _AgentEditor extends StatefulWidget {
  const _AgentEditor({required this.agent});
  final Map<String, Object?> agent;
  @override
  State<_AgentEditor> createState() => _AgentEditorState();
}

class _AgentEditorState extends State<_AgentEditor> {
  late final name = TextEditingController(text: '${widget.agent['name']}');
  late final when = TextEditingController(text: '${widget.agent['transfer_when'] ?? ''}');
  late final greeting = TextEditingController(text: '${widget.agent['greeting'] ?? ''}');
  late final instructions = TextEditingController(text: '${widget.agent['instructions'] ?? ''}');
  late final number = TextEditingController(text: '${access['number'] ?? ''}');
  late Map<String, dynamic> access = (() {
    try {
      return (jsonDecode('${widget.agent['access'] ?? '{}'}') as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  })();
  late String? voice = widget.agent['voice'] as String?;
  late bool enabled = widget.agent['enabled'] == 1;
  List<Map<String, Object?>> servers = [], skills = [], docs = [], devices = [];

  bool get human => widget.agent['handles'] == 'human';
  Set<String> get abilities => access['abilities'] is List
      ? {for (final v in access['abilities'] as List) '$v'}
      : (widget.agent['handles'] == 'incoming' ? {'message'} : <String>{});
  bool get entry => widget.agent['handles'] == 'incoming';

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    () async {
      final sv = await s.db.all('mcp_servers', orderBy: 'id');
      final sk = await s.db.all('skills', orderBy: 'id');
      final dc = await s.db.all('knowledge', orderBy: 'id');
      final dv = await s.db.all('devices', orderBy: 'id');
      if (mounted) {
        setState(() {
          servers = sv;
          devices = dv;
          skills = sk;
          docs = [for (final d in dc) if (d['name'] != 'Past conversations' && !'${d['name']}'.startsWith('MCP: ') && !'${d['name']}'.startsWith('Skill: ')) d];
        });
      }
    }();
  }

  Set<int>? _ids(String k) => access[k] is List ? {for (final v in access[k] as List) (v as num).toInt()} : null;

  Widget _choose(String key, String title, List<Map<String, Object?>> items) {
    final ids = _ids(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Eyebrow(title)),
        Muted('Everything ', size: 12),
        Transform.scale(scale: .7, child: Switch(value: ids == null, onChanged: (v) => setState(() => access[key] = v ? null : <int>[]))),
      ]),
      if (ids != null)
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (items.isEmpty) const Muted('None yet', size: 12),
          for (final i in items)
            FilterChip(
              label: Text('${i['name']}', style: const TextStyle(fontSize: 12)),
              selected: ids.contains(i['id']),
              onSelected: (on) => setState(() => access[key] = (on ? {...ids, i['id'] as int} : (ids..remove(i['id']))).toList()),
            ),
        ]),
      const SizedBox(height: 10),
    ]);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    access.removeWhere((_, v) => v == null);
    if (human) access['number'] = number.text.trim();
    await s.db.update('agents', widget.agent['id'] as int, {
      'name': name.text.trim().isEmpty ? 'Agent' : name.text.trim(),
      'transfer_when': when.text.trim(),
      'greeting': greeting.text.trim(),
      'instructions': instructions.text.trim(),
      'voice': voice,
      'access': jsonEncode(access),
      'enabled': enabled ? 1 : 0,
    });
    await s.log('Updated ${human ? 'person' : 'agent'} ${name.text.trim()} in the call flow');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final voices = <String, String>{
      '': 'Default for the language',
      for (final l in voiceOptions.entries)
        for (final v in l.value.entries) v.key: '${v.value} (${l.key.toUpperCase()})',
    };
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(human ? Icons.person_outline : Icons.smart_toy_outlined, color: human ? LL.green : LL.amber),
              const SizedBox(width: 10),
              Expanded(child: Text(human ? 'Person' : (entry ? 'Answers calls' : 'AI agent'), style: displayStyle(context, 20))),
              if (!entry) Muted('On '),
              if (!entry) Switch(value: enabled, onChanged: (v) => setState(() => enabled = v)),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Field(label: 'Name', child: TextField(controller: name)),
                  const SizedBox(height: 12),
                  if (!entry)
                    Field(
                      label: 'Pass the call here when…',
                      hint: human ? 'e.g. The caller asks for a manager, or has a complaint.' : 'e.g. The caller wants to place a takeaway order.',
                      child: TextField(controller: when, maxLines: 2),
                    ),
                  if (human) ...[
                    const SizedBox(height: 12),
                    Field(
                      label: 'Ring their LocalAILine app',
                      hint: 'A phone paired with this computer. They answer in the app; if not, their number is rung.',
                      child: Dropdown(
                        value: '${access['device'] ?? ''}',
                        items: {'': 'Don’t use the app', for (final d in devices) '${d['id']}': '${d['name']}'},
                        onChanged: (v) => setState(() => v.isEmpty ? access.remove('device') : access['device'] = int.parse(v)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Field(label: 'Their phone number', hint: 'Ava rings this number, briefs them, then connects the caller.', child: TextField(controller: number, decoration: const InputDecoration(hintText: '+44 7700 900123'))),
                  ] else ...[
                    if (entry) Field(label: 'First thing callers hear', child: TextField(controller: greeting, maxLines: 2)),
                    const SizedBox(height: 12),
                    Field(label: 'Voice', child: Dropdown(value: voice ?? '', items: voices, onChanged: (v) => setState(() => voice = v.isEmpty ? null : v))),
                    const SizedBox(height: 12),
                    Field(label: 'Instructions', hint: 'What this agent does, written like a brief to a person.', child: TextField(controller: instructions, maxLines: 5)),
                    const SizedBox(height: 16),
                    const Text('What this agent may use', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Muted('Less is faster: give each agent only what its job needs.', size: 12),
                    const SizedBox(height: 10),
                    Eyebrow('Can do on calls'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in Abilities.labels.entries)
                        FilterChip(
                          label: Text(e.value, style: const TextStyle(fontSize: 12)),
                          selected: abilities.contains(e.key),
                          onSelected: (on) => setState(() => access['abilities'] = (on ? {...abilities, e.key} : (abilities..remove(e.key))).toList()),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    _choose('tools', 'Connected systems', servers),
                    _choose('skills', 'Skills', skills),
                    _choose('docs', 'Documents', docs),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (!entry)
                Btn('Delete', kind: BtnKind.ghost, icon: Icons.delete_outline, onPressed: () async {
                  final s = context.read<AppState>();
                  await s.db.delete('agents', widget.agent['id'] as int);
                  await s.log('Removed ${name.text} from the call flow');
                  if (context.mounted) Navigator.pop(context);
                }),
              const Spacer(),
              Btn('Cancel', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Btn('Save', kind: BtnKind.primary, onPressed: _save),
            ]),
          ]),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
