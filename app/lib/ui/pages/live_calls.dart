import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// The calls going on right now: how many lines are busy, and who is speaking on each.
class LiveCallsPanel extends StatelessWidget {
  const LiveCallsPanel({super.key, this.always = false});

  /// Show it even with no calls ("No calls right now").
  final bool always;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final calls = s.liveCalls.entries.where((e) => DateTime.now().difference(e.value.at) < const Duration(minutes: 2)).toList();
    if (calls.isEmpty && !always) return const SizedBox.shrink();
    final speaking = calls.where((e) => e.value.agent == 'speaking').length;
    final thinking = calls.where((e) => e.value.agent == 'thinking').length;
    final callers = calls.where((e) => e.value.caller == 'speaking').length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.call, size: 18, color: calls.isEmpty ? context.c.muted : context.c.greenInk),
            const SizedBox(width: 10),
            Text(calls.isEmpty ? 'No calls right now' : '${calls.length} call${calls.length == 1 ? '' : 's'} on the line now',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const Spacer(),
            if (calls.isNotEmpty) ...[
              Pill('AI speaking $speaking', tone: speaking > 0 ? Tone.green : Tone.neutral),
              const SizedBox(width: 6),
              Pill('Thinking $thinking', tone: thinking > 0 ? Tone.amber : Tone.neutral),
              const SizedBox(width: 6),
              Pill('Callers speaking $callers', tone: callers > 0 ? Tone.blue : Tone.neutral),
            ],
          ]),
          for (final e in calls) ...[
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 28),
              Expanded(child: Muted(e.value.number.isEmpty ? e.key : e.value.number, mono: true, size: 12.5)),
              Muted(switch ((e.value.agent, e.value.caller)) {
                (_, 'speaking') => 'caller is speaking',
                ('speaking', _) => 'AI is speaking',
                ('thinking', _) => 'AI is thinking',
                _ => 'listening',
              }, size: 12.5),
            ]),
          ],
        ]),
      ),
    );
  }
}
