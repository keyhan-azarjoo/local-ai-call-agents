import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// The calls going on right now: how many lines are busy, who is speaking on each, and what is
/// being said, word by word as it is said. Finished conversations stay below for a while.
class LiveCallsPanel extends StatelessWidget {
  const LiveCallsPanel({super.key, this.always = false});

  /// Show it even with no calls ("No calls right now"), with the recent conversations.
  final bool always;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final calls = s.liveCalls.entries
        .where(
          (e) =>
              DateTime.now().difference(e.value.at) <
              const Duration(minutes: 2),
        )
        .toList();
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
                Icon(
                  Icons.call,
                  size: 18,
                  color: calls.isEmpty ? context.c.muted : context.c.greenInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    calls.isEmpty
                        ? 'No calls right now'
                        : '${calls.length} call${calls.length == 1 ? '' : 's'} on the line now',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (calls.isNotEmpty)
                  Flexible(
                    flex: 2,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          'AI speaking $speaking',
                          tone: speaking > 0 ? Tone.green : Tone.neutral,
                        ),
                        Pill(
                          'Thinking $thinking',
                          tone: thinking > 0 ? Tone.amber : Tone.neutral,
                        ),
                        Pill(
                          'Callers speaking $callers',
                          tone: callers > 0 ? Tone.blue : Tone.neutral,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            for (final e in calls) ...[
              const SizedBox(height: 12),
              _LiveCall(
                number: e.value.number.isEmpty ? e.key : e.value.number,
                state: switch ((e.value.agent, e.value.caller)) {
                  (_, 'speaking') => 'caller is speaking',
                  ('speaking', _) => 'AI is speaking',
                  ('thinking', _) => 'AI is thinking',
                  _ => 'listening',
                },
                test: s
                    .scenarioRuns
                    .isNotEmpty, // (tests never place or take real calls)
                lines: s.liveText[e.key] ?? const [],
              ),
            ],
            if (always && s.recentLive.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Recent conversations',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              for (final r in s.recentLive)
                _RecentCall(
                  r.number.isEmpty ? r.room : r.number,
                  r.ended,
                  r.lines,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One call on the line: its conversation so far, newest at the bottom.
class _LiveCall extends StatelessWidget {
  const _LiveCall({
    required this.number,
    required this.state,
    required this.test,
    required this.lines,
  });
  final String number, state;
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
            if (test) ...[
              const SizedBox(width: 8),
              const Pill('test call', tone: Tone.neutral),
            ],
            const Spacer(),
            Muted(state, size: 12.5),
          ],
        ),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          const Muted('Waiting for the first words…', size: 12.5)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            // Reversed: it stays scrolled to the newest words as they arrive.
            child: ListView(
              reverse: true,
              shrinkWrap: true,
              children: [for (final l in lines.reversed) LiveBubble(l)],
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: context.c.muted),
            const SizedBox(width: 6),
            Muted(widget.number, mono: true, size: 12.5),
            const SizedBox(width: 10),
            Expanded(child: Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 10),
            Muted('ended $t · ${widget.lines.where((l) => l.who != 'note').length} lines', size: 12),
          ]),
        ),
      ),
      if (open) ...[for (final l in widget.lines) LiveBubble(l), const SizedBox(height: 8)],
    ]);
  }
}

/// One line as it is being said: the caller on the left, the AI on the right, notes (hold music,
/// call ended) in the middle. Unfinished words are shown as still coming.
class LiveBubble extends StatelessWidget {
  const LiveBubble(this.line, {super.key});
  final LiveLine line;

  @override
  Widget build(BuildContext context) {
    final at =
        '${line.at.hour.toString().padLeft(2, '0')}:${line.at.minute.toString().padLeft(2, '0')}:${line.at.second.toString().padLeft(2, '0')}';
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
        decoration: BoxDecoration(
          color: caller ? context.c.blueSoft : context.c.greenSoft,
          borderRadius: BorderRadius.circular(LL.rSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Muted(
              '${caller ? 'Caller' : (line.name?.isNotEmpty == true ? line.name! : 'AI')} · $at${line.done
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
                fontStyle: caller && !line.done
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: caller && !line.done ? context.c.muted : context.c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
