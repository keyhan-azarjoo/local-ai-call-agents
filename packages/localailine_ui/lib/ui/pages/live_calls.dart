import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import 'package:localailine_ui/app_model.dart';
import '../../state/call_monitor.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// A conversation as plain text ("Caller: …", "AI: …"), to paste somewhere.
String conversationText(List<LiveLine> lines) => [
  for (final l in lines)
    if (l.text.trim().isNotEmpty)
      '${l.who == 'note'
          ? 'Note'
          : l.name?.isNotEmpty == true
          ? l.name
          : l.who == 'caller'
          ? 'Caller'
          : 'AI'}: ${l.text.trim()}',
].join('\n');

Future<void> copyConversation(BuildContext context, List<LiveLine> lines) async {
  final s = context.read<AppModel>();
  await Clipboard.setData(ClipboardData(text: conversationText(lines)));
  s.toast('Conversation copied');
}

/// The calls going on right now: how many lines are busy, who is speaking on each, and what is
/// being said, word by word as it is said. Finished conversations stay below for a while.
class LiveCallsPanel extends StatelessWidget {
  const LiveCallsPanel({super.key, this.always = false});

  /// Show it even with no calls ("No calls right now"), with the recent conversations.
  final bool always;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppModel>();
    final calls = s.liveCalls.entries.where((e) => DateTime.now().difference(e.value.at) < const Duration(minutes: 2)).toList();
    if (calls.isEmpty && !always) return const SizedBox.shrink();
    final speaking = calls.where((e) => e.value.agent == 'speaking').length;
    final thinking = calls.where((e) => e.value.agent == 'thinking').length;
    final callers = calls.where((e) => e.value.caller == 'speaking').length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.call, size: 18, color: calls.isEmpty ? context.c.muted : context.c.greenInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    calls.isEmpty ? 'No calls right now' : '${calls.length} call${calls.length == 1 ? '' : 's'} on the line now',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (always && s.canVoiceTest) ...[
                  Btn(
                    s.voiceTestPorts.isEmpty ? 'Voice test call' : 'Voice test call (${s.voiceTestPorts.length} on)',
                    icon: Icons.record_voice_over_outlined,
                    small: true,
                    onPressed: () => showVoiceTestDialog(context),
                  ),
                  const SizedBox(width: 10),
                ],
                if (calls.isNotEmpty)
                  Flexible(
                    flex: 2,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill('AI speaking $speaking', tone: speaking > 0 ? Tone.green : Tone.neutral),
                        Pill('Thinking $thinking', tone: thinking > 0 ? Tone.amber : Tone.neutral),
                        Pill('Callers speaking $callers', tone: callers > 0 ? Tone.blue : Tone.neutral),
                      ],
                    ),
                  ),
              ],
            ),
            for (final e in calls) ...[
              const SizedBox(height: 12),
              _LiveCall(
                room: e.key,
                number: e.value.number.isEmpty ? e.key : e.value.number,
                state: switch ((e.value.agent, e.value.caller)) {
                  _ when s.ringing.containsKey(e.key) => 'ringing you',
                  (_, 'speaking') => s.callerAs[e.key] != null ? '${s.callerAs[e.key]} (as caller) is speaking' : 'caller is speaking',
                  _ when s.takenOver[e.key] != null =>
                    s.ownerSpeaking.contains(e.key) ? '${s.takenOver[e.key]} is speaking' : '${s.takenOver[e.key]} is on the call',
                  ('speaking', _) => 'AI is speaking',
                  ('thinking', _) => 'AI is thinking',
                  _ => 'listening',
                },
                test: s.testsRunning, // (tests never place or take real calls)
                lines: s.liveText[e.key] ?? const [],
              ),
            ],
            if (always && s.recentLive.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Recent conversations', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 4),
              for (final r in s.recentLive) _RecentCall(r.number.isEmpty ? r.room : r.number, r.ended, r.lines),
            ],
          ],
        ),
      ),
    );
  }
}

/// One call on the line: its conversation so far, newest at the bottom.
class _LiveCall extends StatelessWidget {
  const _LiveCall({required this.room, required this.number, required this.state, required this.test, required this.lines});
  final String room, number, state;
  final bool test;
  final List<LiveLine> lines;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: context.c.line),
      borderRadius: BorderRadius.circular(LL.rSm),
    ),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: Muted(number, mono: true, size: 12.5)),
            if (test || CallMonitor.isVoiceTest(room)) ...[const SizedBox(width: 8), const Pill('test call', tone: Tone.neutral)],
            const Spacer(),
            Muted(state, size: 12.5),
            if (lines.isNotEmpty)
              IconButton(
                tooltip: 'Copy conversation',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 15),
                onPressed: () => copyConversation(context, lines),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CallControls(room: room),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          Muted(context.select<AppModel, bool>((s) => s.ringing.containsKey(room)) ? 'Ringing you. Answer to talk to the caller yourself.' : 'Waiting for the first words…', size: 12.5)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            // Reversed: it stays scrolled to the newest words as they arrive.
            child: ListView(reverse: true, shrinkWrap: true, children: [for (final l in lines.reversed) LiveBubble(l)]),
          ),
      ],
    ),
  );
}

/// The owner on a live call: listen in on the speakers, take over from the AI (and hand back or
/// hang up), and on voice test calls speak as the caller. See [CallMonitor].
class CallControls extends StatelessWidget {
  const CallControls({super.key, required this.room});
  final String room;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppModel>();
    final m = s.callMonitor;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final mode = m.modeOf(room);
        final asCaller = context.select<AppModel, bool>((s) => s.callerAs.containsKey(room));
        final voiceTest = CallMonitor.isVoiceTest(room);
        final owner = s.ownerName;
        final busy = m.callerBusy(room);
        final on = mode == MonitorMode.listening || mode == MonitorMode.takenOver;
        // A call ringing you (the line rings you first): answer it here, or let the AI take it.
        final ringing = context.select<AppModel, bool>((s) => s.ringing.containsKey(room));
        if (ringing && mode != MonitorMode.takenOver && mode != MonitorMode.connecting) {
          return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Btn('Answer', icon: Icons.call, small: true, kind: BtnKind.green, onPressed: () => m.takeOver(room)),
            Btn('Let the AI answer', icon: Icons.smart_toy_outlined, small: true, onPressed: () => s.releaseCall(room)),
          ]);
        }
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            switch (mode) {
              MonitorMode.off when asCaller => const Muted('Listening through the test caller', size: 12),
              MonitorMode.off => Btn('Listen', icon: Icons.headphones, small: true, onPressed: () => m.listen(room)),
              MonitorMode.connecting => Btn('Connecting…', icon: Icons.headphones, small: true, kind: BtnKind.ghost, onPressed: () => m.stop(room)),
              MonitorMode.listening => Btn('Stop listening', icon: Icons.headset_off, small: true, kind: BtnKind.ghost, onPressed: () => m.stop(room)),
              MonitorMode.takenOver => Btn(
                m.mutedOn(room) ? 'Unmute' : 'Mute',
                icon: m.mutedOn(room) ? Icons.mic_off : Icons.mic,
                small: true,
                kind: BtnKind.ghost,
                onPressed: () => m.toggleMute(room),
              ),
              MonitorMode.handingBack => const Btn('Handing back…', icon: Icons.smart_toy_outlined, small: true, kind: BtnKind.ghost),
            },
            // (One at a time: in place of the AI, or in place of the caller — not both.)
            if ((mode == MonitorMode.off || mode == MonitorMode.listening) && !asCaller)
              Btn('Take over', icon: Icons.record_voice_over, small: true, kind: BtnKind.amber, onPressed: () => m.takeOver(room)),
            if (mode == MonitorMode.takenOver) ...[
              Btn('Hand back to AI', icon: Icons.smart_toy_outlined, small: true, kind: BtnKind.green, onPressed: () => m.handBack(room)),
              Btn('End call', icon: Icons.call_end, small: true, kind: BtnKind.danger, onPressed: () => m.endCall(room)),
            ],
            if (voiceTest && mode != MonitorMode.takenOver && mode != MonitorMode.handingBack)
              asCaller
                  ? Btn(
                      busy ? 'Handing back…' : 'Hand back',
                      icon: Icons.person_off_outlined,
                      small: true,
                      onPressed: busy ? null : () => m.speakAsCaller(room, back: true),
                    )
                  : Btn(
                      busy ? 'Switching…' : 'Speak as the caller',
                      icon: Icons.person_outline,
                      small: true,
                      onPressed: busy ? null : () => m.speakAsCaller(room),
                    ),
            if (on) _Level(level: m.levelOf(room), muted: m.mutedOn(room)),
            if (on)
              Muted(switch ((mode, m.speakingOn(room))) {
                (MonitorMode.takenOver, 'owner') => 'You’re speaking',
                (MonitorMode.takenOver, 'caller') => 'The caller is speaking',
                (MonitorMode.takenOver, _) => m.mutedOn(room) ? 'On the call · microphone off' : 'On the call as $owner · microphone on',
                (_, 'caller') => 'Listening · the caller is speaking',
                (_, 'agent') => 'Listening · the AI is speaking',
                _ => 'Listening on this computer’s speakers',
              }, size: 12),
            if (asCaller && mode != MonitorMode.takenOver) Muted('You’re the caller (your microphone, through the test caller)', size: 12),
          ],
        );
      },
    );
  }
}

/// How loud the call is right now (a small bar), so it's clear audio is coming through.
class _Level extends StatelessWidget {
  const _Level({required this.level, required this.muted});
  final double level;
  final bool muted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Audio level',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 4,
            height: 6.0 + i * 2.5,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: level > i * .12 + .02 ? (muted ? context.c.muted : context.c.greenInk) : context.c.line,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    ),
  );
}

/// A finished conversation, opened to read it.
class _RecentCall extends StatefulWidget {
  const _RecentCall(this.number, this.ended, this.lines);
  final String number;
  final DateTime ended;
  final List<LiveLine> lines;

  @override
  State<_RecentCall> createState() => _RecentCallState();
}

class _RecentCallState extends State<_RecentCall> {
  var open = false;

  @override
  Widget build(BuildContext context) {
    final first = widget.lines.where((l) => l.who == 'caller').firstOrNull?.text ?? '';
    final e = widget.ended;
    final t = '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: context.c.muted),
                const SizedBox(width: 6),
                Muted(widget.number, mono: true, size: 12.5),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Muted('ended $t · ${widget.lines.where((l) => l.who != 'note').length} lines', size: 12),
                IconButton(
                  tooltip: 'Copy conversation',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 15),
                  onPressed: () => copyConversation(context, widget.lines),
                ),
              ],
            ),
          ),
        ),
        if (open) ...[for (final l in widget.lines) LiveBubble(l), const SizedBox(height: 8)],
      ],
    );
  }
}

/// One line as it is being said: the caller on the left, the AI on the right, notes (hold music,
/// call ended) in the middle. Unfinished words are shown as still coming.
class LiveBubble extends StatelessWidget {
  const LiveBubble(this.line, {super.key});
  final LiveLine line;

  @override
  Widget build(BuildContext context) {
    final at = '${line.at.hour.toString().padLeft(2, '0')}:${line.at.minute.toString().padLeft(2, '0')}:${line.at.second.toString().padLeft(2, '0')}';
    if (line.who == 'note') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: Muted('${line.text}  ·  $at', size: 12)),
      );
    }
    final caller = line.who == 'caller';
    return Align(
      alignment: caller ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: caller ? context.c.blueSoft : context.c.greenSoft, borderRadius: BorderRadius.circular(LL.rSm)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Muted(
              '${caller ? (line.name?.isNotEmpty == true ? line.name! : 'Caller') : (line.name?.isNotEmpty == true ? line.name! : 'AI')} · $at${line.done
                  ? ''
                  : caller
                  ? ' · hearing…'
                  : ' · speaking…'}',
              size: 11,
            ),
            const SizedBox(height: 2),
            Text(
              line.done ? line.text : '${line.text} ▍',
              style: TextStyle(
                fontSize: 13.5,
                fontStyle: caller && !line.done ? FontStyle.italic : FontStyle.normal,
                color: caller && !line.done ? context.c.muted : context.c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rings the test line with a simulated caller who speaks (a real voice, never a real phone call):
/// the call shows above like any other, to listen to, take over, or continue as the caller.
Future<void> showVoiceTestDialog(BuildContext context) async {
  final s = context.read<AppModel>();
  final personas = await s.voicePersonas();
  final answerers = await s.voiceTestAgents();
  if (!context.mounted || personas.isEmpty) return;
  var pick = personas.first['id'] as String;
  // Each caller rings its own kind of business (its receptionist), else the main assistant.
  const businesses = {'restaurant': 'Trattoria Bella', 'barber': 'Kings Cut Barbers', 'salon': 'Studio Lumière', 'clinic': 'Riverside Dental', 'hotel': 'The Harbour House'};
  int? answererFor(String persona) {
    final b = businesses['${personas.firstWhere((p) => p['id'] == persona)['business']}'];
    return answerers.where((a) => b != null && a.label.endsWith(' · $b')).firstOrNull?.id ?? answerers.firstOrNull?.id;
  }
  var agent = answererFor(pick);
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Voice test call'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Muted(
                'A pretend caller rings your test line and talks to your assistant out loud. No real phone call is made. '
                'Once it’s on the line: Listen, Take over (you replace the AI), or Speak as the caller (you replace the caller).',
              ),
              const SizedBox(height: 14),
              DropdownButton<String>(
                isExpanded: true,
                value: pick,
                items: [
                  for (final p in personas)
                    DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        '${p['name']} · ${p['business']} · ${(p['language'] as String).toUpperCase()}${(p['tactics'] as List?)?.isNotEmpty == true ? ' · tricky' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => set(() => pick = v ?? pick),
              ),
              const SizedBox(height: 8),
              Muted('${personas.firstWhere((p) => p['id'] == pick)['goal']}', size: 12.5),
            ],
          ),
        ),
        actions: [
          if (s.voiceTestPorts.isNotEmpty)
            TextButton(
              onPressed: () {
                s.stopVoiceTests();
                Navigator.pop(ctx);
              },
              child: const Text('Hang up test calls'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              s.startVoiceTest(pick, agentId: agent);
            },
            child: const Text('Ring the test line'),
          ),
        ],
      ),
    ),
  );
}
