import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/companion/host_server.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// On the main computer: pair phones and other computers, and test ringing.
class PhonesSection extends StatelessWidget {
  const PhonesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final host = s.host;
    return Section(
      title: 'Answer on your phone',
      trailing: Wrap(spacing: 8, children: [
        Btn('Test ring', icon: Icons.notifications_active_outlined, small: true, onPressed: host == null ? null : s.testRing),
        Btn('Pair a phone', icon: Icons.add, small: true, kind: BtnKind.primary, onPressed: host == null ? null : () => showPairDialog(context)),
      ]),
      children: [
        if (host == null || !host.running)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Muted(host?.startError ?? 'Pairing is only available on the main computer.'),
          )
        else
          FutureBuilder(
            future: s.db.all('devices'),
            builder: (context, snap) {
              final devices = snap.data ?? [];
              if (devices.isEmpty) {
                return const EmptyState(
                  icon: Icons.smartphone_outlined,
                  title: 'No phone paired yet',
                  body: 'Install LocalAILine on your phone, choose “Connect to my LocalAILine computer”, then press Pair a phone here.',
                );
              }
              return Column(children: [
                for (final d in devices)
                  Tile(
                    last: d == devices.last,
                    leading: LogoBox(child: Icon(d['platform'] == 'ios' || d['platform'] == 'android' ? Icons.smartphone_outlined : Icons.computer_outlined)),
                    title: Text(d['name'] as String),
                    subtitle: Muted(host.live.containsKey(d['id'])
                        ? 'Connected now'
                        : d['last_seen'] == null
                            ? 'Paired · not connected yet'
                            : 'Last seen ${ago(d['last_seen'] as int)}'),
                    trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Lamp(host.live.containsKey(d['id']) ? LampState.on : LampState.off),
                      const Muted('Ring'),
                      Transform.scale(
                        scale: .8,
                        child: Switch(value: d['ring'] == 1, onChanged: (v) async {
                          await s.db.update('devices', d['id'] as int, {'ring': v ? 1 : 0});
                          s.refresh();
                        }),
                      ),
                      IconButton(
                        tooltip: 'Remove device',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await host.live.remove(d['id'])?.socket.close();
                          await s.db.delete('devices', d['id'] as int);
                          await s.log('Removed device ${d['name']}');
                          s.refresh();
                        },
                      ),
                    ]),
                  ),
              ]);
            },
          ),
      ],
    );
  }
}

Future<void> showPairDialog(BuildContext context) async {
  final s = context.read<AppState>();
  final code = s.host!.newPairingCode();
  final addrs = await HostServer.localAddresses();
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Pair a phone', style: displayStyle(c, 22)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('On your phone, open LocalAILine and choose “Connect to my LocalAILine computer”.'),
          const SizedBox(height: 16),
          const Eyebrow('Pairing code'),
          const SizedBox(height: 4),
          SelectableText(code, style: const TextStyle(fontFamily: LL.mono, fontSize: 34, letterSpacing: 6, fontWeight: FontWeight.w500)),
          const Muted('Valid for 10 minutes, for one device.'),
          const SizedBox(height: 14),
          const Eyebrow('Computer address'),
          const SizedBox(height: 4),
          if (addrs.isEmpty) const Muted('No network found. Connect this computer to Wi-Fi or Ethernet.'),
          for (final a in addrs) SelectableText('$a:${s.host!.port}', style: const TextStyle(fontFamily: LL.mono, fontSize: 16)),
          const SizedBox(height: 10),
          const Muted('The phone usually finds this computer by itself. Both must be on the same network (or the same Tailscale network).'),
        ]),
      ),
      actions: [Btn('Done', kind: BtnKind.primary, onPressed: () => Navigator.pop(c))],
    ),
  );
  s.refresh();
}
