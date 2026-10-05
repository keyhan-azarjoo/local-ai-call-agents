import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../services/companion/host_client.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'auth_pages.dart' show Brand;
import 'widgets.dart';

// ============================ Pairing (on the phone) ============================

/// "Connect to my LocalAILine computer": find it, enter the code, done.
class CompanionSetup extends StatefulWidget {
  const CompanionSetup({super.key, this.onBack});
  final VoidCallback? onBack;
  @override
  State<CompanionSetup> createState() => _CompanionSetupState();
}

class _CompanionSetupState extends State<CompanionSetup> {
  final address = TextEditingController();
  final code = TextEditingController();
  List<FoundHost> found = [];
  bool searching = true, busy = false;
  String? hostName, error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => searching = true);
    final f = await HostClient.discover();
    if (!mounted) return;
    setState(() {
      found = f;
      searching = false;
      if (f.length == 1 && address.text.isEmpty) address.text = '${f.first.address}:${f.first.port}';
    });
  }

  Future<void> _pair() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final base = HostClient.normalize(address.text);
      hostName = await HostClient.hello(base);
      if (!mounted) return;
      await context.read<AppState>().pairWith(base, code.text.trim());
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: LL.navy, borderRadius: BorderRadius.circular(LL.r)),
                    child: const Brand(),
                  ),
                  const SizedBox(height: 24),
                  Text('Connect to your LocalAILine computer', style: displayStyle(context, 26)),
                  const SizedBox(height: 8),
                  const Muted('On the computer, open Phone line → Answer on your phone → Pair a phone. It shows the address and a 6-digit code.', size: 14),
                  const SizedBox(height: 20),
                  if (searching)
                    const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Looking on this network…')])
                  else if (found.isNotEmpty) ...[
                    const Eyebrow('Found on this network'),
                    const SizedBox(height: 6),
                    for (final h in found)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => setState(() => address.text = '${h.address}:${h.port}'),
                          child: Panel(
                            padding: const EdgeInsets.all(12),
                            borderColor: address.text == '${h.address}:${h.port}' ? LL.navy3 : null,
                            child: Row(children: [
                              const Icon(Icons.computer_outlined, size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Muted(h.address, mono: true),
                            ]),
                          ),
                        ),
                      ),
                  ] else
                    Row(children: [
                      const Expanded(child: Muted('No computer found automatically. Type its address below.')),
                      Btn('Search again', small: true, onPressed: _search),
                    ]),
                  const SizedBox(height: 14),
                  Field(
                    label: 'Computer address',
                    hint: 'Shown on the computer, e.g. 192.168.1.20',
                    child: TextField(controller: address, keyboardType: TextInputType.url, autocorrect: false),
                  ),
                  const SizedBox(height: 14),
                  Field(
                    label: 'Pairing code',
                    child: TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: LL.mono, fontSize: 20, letterSpacing: 4),
                      decoration: const InputDecoration(hintText: '000000'),
                      onSubmitted: (_) => _pair(),
                    ),
                  ),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: LL.red))),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: Btn(busy ? 'Connecting…' : 'Connect', kind: BtnKind.primary, large: true, onPressed: busy ? null : _pair),
                  ),
                  if (widget.onBack != null) ...[
                    const SizedBox(height: 10),
                    Center(child: Btn('Back', kind: BtnKind.ghost, onPressed: widget.onBack)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}

// ============================ Ringing ============================

/// Full-screen ring on any device; shows over every page.
class RingOverlay extends StatelessWidget {
  const RingOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.incoming;
    return Stack(children: [
      child,
      if (s.ringStatus != null)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(child: Material(color: Colors.transparent, child: Pill(s.ringStatus!, tone: Tone.amber, lamp: LampState.ring))),
        ),
      if (r != null)
        Positioned.fill(
          child: Material(
            color: Colors.black54,
            child: Center(
              child: Container(
                width: 360,
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(color: LL.navy, borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Incoming call · ${r['line']}', style: const TextStyle(color: Color(0xFF8FA6C2), fontFamily: LL.mono, fontSize: 11)),
                  const SizedBox(height: 14),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: LL.navy3, border: Border.all(color: LL.amber, width: 2)),
                    child: const Icon(Icons.call, color: LL.amber, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text('${r['from']}', style: const TextStyle(fontFamily: LL.display, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('${r['number']}', style: const TextStyle(fontFamily: LL.mono, fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Ava answers in ${r['seconds']}s if you don’t', style: const TextStyle(color: LL.navText, fontSize: 12.5)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Btn('Answer here', kind: BtnKind.green, onPressed: () => s.answerIncoming('me'))),
                    const SizedBox(width: 8),
                    Expanded(child: Btn('Let Ava', kind: BtnKind.amber, onPressed: () => s.answerIncoming('ai'))),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: Btn('Decline', kind: BtnKind.danger, onPressed: () => s.answerIncoming('decline'))),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ============================ Paired device app ============================

enum RemotePage { home, chat, talk, calls, settings }

class CompanionShell extends StatefulWidget {
  const CompanionShell({super.key});
  @override
  State<CompanionShell> createState() => _CompanionShellState();
}

class _CompanionShellState extends State<CompanionShell> {
  RemotePage page = RemotePage.home;

  static const _items = {
    RemotePage.home: ('Home', Icons.space_dashboard_outlined),
    RemotePage.chat: ('Chat', Icons.chat_bubble_outline_rounded),
    RemotePage.talk: ('Talk', Icons.mic_none_rounded),
    RemotePage.calls: ('Calls', Icons.call_outlined),
    RemotePage.settings: ('Settings', Icons.settings_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final body = switch (page) {
      RemotePage.home => _RemoteHome(go: (p) => setState(() => page = p)),
      RemotePage.chat => const _RemoteChat(),
      RemotePage.talk => const _RemoteTalk(),
      RemotePage.calls => const _RemoteCalls(),
      RemotePage.settings => const _RemoteSettings(),
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.c.shell,
        foregroundColor: Colors.white,
        title: const Brand(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Pill(s.remote?.connected == true ? 'Connected' : 'Reconnecting…',
                tone: s.remote?.connected == true ? Tone.green : Tone.amber, lamp: s.remote?.connected == true ? LampState.on : LampState.ring),
          ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page.index,
        onDestinationSelected: (i) => setState(() => page = RemotePage.values[i]),
        destinations: [for (final e in _items.values) NavigationDestination(icon: Icon(e.$2), label: e.$1)],
      ),
    );
  }
}

class _RemoteHome extends StatefulWidget {
  const _RemoteHome({required this.go});
  final void Function(RemotePage) go;
  @override
  State<_RemoteHome> createState() => _RemoteHomeState();
}

class _RemoteHomeState extends State<_RemoteHome> {
  Map? status;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await context.read<AppState>().remote!.get('status');
      if (mounted) setState(() => status = st as Map);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow('Connected to ${s.remoteName ?? 'your computer'}'),
            const SizedBox(height: 8),
            Text(
              status == null
                  ? (error ?? 'Loading…')
                  : status!['answering'] == true
                      ? '${status!['agent']} is answering your calls.'
                      : '${status!['agent']} is not answering.',
              style: displayStyle(context, 24),
            ),
            if (status != null) ...[
              const SizedBox(height: 6),
              Muted(status!['ai'] == null ? 'The AI isn’t set up on the computer yet.' : 'Thinking with ${status!['ai']}'),
              const SizedBox(height: 10),
              SwitchRow('Answering', value: status!['answering'] == true, onChanged: (v) async {
                await s.remote!.post('answering', {'on': v});
                _load();
              }),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        const Panel(
          child: Row(children: [
            Icon(Icons.notifications_active_outlined, color: LL.amber),
            SizedBox(width: 12),
            Expanded(child: Text('Keep this app open to get rings from the computer. It rings here first, then Ava answers if you don’t.')),
          ]),
        ),
        const SizedBox(height: 12),
        Btn('Talk to Ava', icon: Icons.mic_none_rounded, kind: BtnKind.amber, large: true, onPressed: () => widget.go(RemotePage.talk)),
        const SizedBox(height: 8),
        Btn('Chat with AI', icon: Icons.chat_bubble_outline_rounded, large: true, onPressed: () => widget.go(RemotePage.chat)),
      ]),
    );
  }
}

class _RemoteChat extends StatefulWidget {
  const _RemoteChat();
  @override
  State<_RemoteChat> createState() => _RemoteChatState();
}

class _RemoteChatState extends State<_RemoteChat> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final msgs = <Map<String, String>>[];
  bool busy = false;

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    input.clear();
    setState(() {
      msgs.add({'role': 'user', 'content': text});
      busy = true;
    });
    try {
      final r = await context.read<AppState>().remote!.post('chat', {
        'messages': [
          {'role': 'system', 'content': 'You are a helpful, concise assistant. Use tools for questions about the user’s data.'},
          ...msgs,
        ]
      }) as Map;
      setState(() => msgs.add({'role': 'assistant', 'content': '${r['reply']}'}));
    } catch (e) {
      setState(() => msgs.add({'role': 'assistant', 'content': 'Couldn’t reply: $e'}));
    } finally {
      if (mounted) setState(() => busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? const Center(child: Muted('Ask anything. The computer’s AI answers.', size: 14))
              : ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
                  for (final m in msgs)
                    Align(
                      alignment: m['role'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(color: m['role'] == 'user' ? LL.navy : context.c.panel, borderRadius: BorderRadius.circular(12)),
                        child: SelectableText(m['content']!, style: TextStyle(color: m['role'] == 'user' ? Colors.white : context.c.ink)),
                      ),
                    ),
                  if (busy) const Padding(padding: EdgeInsets.all(8), child: Muted('Thinking…')),
                ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(controller: input, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message the AI…'))),
            const SizedBox(width: 8),
            Btn('Send', kind: BtnKind.primary, onPressed: busy ? null : _send),
          ]),
        ),
      ]);
}

class _RemoteTalk extends StatefulWidget {
  const _RemoteTalk();
  @override
  State<_RemoteTalk> createState() => _RemoteTalkState();
}

class _RemoteTalkState extends State<_RemoteTalk> {
  final rec = AudioRecorder();
  final player = AudioPlayer();
  final turns = <(String, String)>[];
  List<Object?> history = [];
  bool listening = false, busy = false;
  String? status;

  @override
  void dispose() {
    rec.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> _turn({String? text, String? audioPath}) async {
    setState(() {
      busy = true;
      status = audioPath != null ? 'Understanding…' : 'Thinking…';
    });
    try {
      final r = await context.read<AppState>().remote!.post('talk', {
        'history': history,
        'text': ?text,
        if (audioPath != null) 'audio': base64Encode(await File(audioPath).readAsBytes()),
      }) as Map;
      history = r['history'] as List;
      setState(() {
        if ('${r['heard']}'.isNotEmpty) turns.add(('You', '${r['heard']}'));
        if ('${r['reply']}'.isNotEmpty) turns.add(('Ava', '${r['reply']}'));
        if ('${r['heard']}'.isEmpty) status = 'I didn’t catch that.';
      });
      if (r['audio'] != null) await player.play(BytesSource(base64Decode(r['audio'] as String)));
    } catch (e) {
      setState(() => status = '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          if (status == 'Thinking…' || status == 'Understanding…') status = null;
        });
      }
    }
  }

  Future<void> _mic() async {
    if (listening) {
      final path = await rec.stop();
      setState(() => listening = false);
      if (path != null) await _turn(audioPath: path);
      return;
    }
    if (!await rec.hasPermission()) {
      setState(() => status = 'Allow microphone access in Settings.');
      return;
    }
    await player.stop();
    final path = p.join((await Directory.systemTemp.createTemp('ll')).path, 'mic.wav');
    await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    setState(() => listening = true);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 12),
        Center(child: Text('Talk to Ava', style: displayStyle(context, 26))),
        const Center(child: Muted('Pretend you are calling. Ava runs on your computer.')),
        const SizedBox(height: 20),
        Center(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : _mic,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle, color: listening ? LL.red : LL.amber),
              child: Icon(listening ? Icons.stop_rounded : Icons.mic_none_rounded, size: 44, color: LL.navy),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: Text(status ?? (listening ? 'Listening… tap to send' : 'Tap to talk'), style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 20),
        for (final (who, text) in turns)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 44, child: Eyebrow(who)),
                Expanded(child: Text(text)),
              ]),
            ),
          ),
      ]);
}

class _RemoteCalls extends StatelessWidget {
  const _RemoteCalls();
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: context.read<AppState>().remote!.get('calls'),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Muted('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final calls = (snap.data as List).cast<Map>();
          if (calls.isEmpty) return const Center(child: Muted('No calls yet.', size: 14));
          return ListView(children: [
            for (final c in calls)
              ListTile(
                leading: Icon(c['direction'] == 'outgoing' ? Icons.phone_forwarded_outlined : Icons.call_received),
                title: Text('${(c['name'] as String?)?.isNotEmpty == true ? c['name'] : c['number']}'),
                subtitle: Text('${c['summary'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(ago(c['started_at'] as int), style: const TextStyle(fontFamily: LL.mono, fontSize: 11)),
              ),
          ]);
        },
      );
}

class _RemoteSettings extends StatelessWidget {
  const _RemoteSettings();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This device', style: displayStyle(context, 17)),
          const SizedBox(height: 8),
          KV([
            ('Name', Text(AppState.deviceName)),
            ('Computer', Text(s.remoteName ?? '')),
            ('Address', Mono(s.remote?.base ?? '')),
          ]),
          const SizedBox(height: 10),
          SwitchRow('Dark appearance', value: s.themeMode == ThemeMode.dark, onChanged: (_) => s.toggleTheme()),
          const SizedBox(height: 10),
          Btn('Disconnect this device', kind: BtnKind.danger, onPressed: s.unpair),
        ]),
      ),
    ]);
  }
}
