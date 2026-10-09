import 'package:flutter/material.dart';
import 'package:localailine_ui/ui/widgets.dart';

import 'devices_section.dart';
import 'live_talk.dart';

/// Pages only the desktop app has: the local voice server and phones paired with this computer.

class VoiceServerPage extends StatelessWidget {
  const VoiceServerPage({super.key});
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHead('Voice server', description: 'The built-in LiveKit server that connects phone calls, this computer and your phone to the assistant.'),
            Grid(cols: 2, children: [
              Panel(child: VoiceEnginePanel()),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text('Phone gateway', style: TextStyle(fontWeight: FontWeight.w600))), Lamp(LampState.off)]),
                  SizedBox(height: 4),
                  Muted('Registers your lines and receives landline calls. Coming in the next milestone.'),
                ]),
              ),
            ]),
          ]);
}

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead('Paired devices', description: 'Phones and other computers connected to this one. Calls ring there first.'),
        PhonesSection(),
      ]);
}
