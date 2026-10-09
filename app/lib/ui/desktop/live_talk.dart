import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import 'package:localailine_model/voice.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine_ui/theme/tokens.dart';
import 'package:localailine_ui/ui/widgets.dart';

class _Line {
  _Line(this.who, this.text);
  final String who; // ai | you
  String text;
}

/// A live, hands-free conversation: you talk, the assistant listens while you speak,
/// answers as soon as you stop, and you can interrupt it at any time.
class LiveTalk extends StatefulWidget {
  const LiveTalk({super.key, required this.mode, required this.name});
  final String mode; // caller | owner
  final String name;
  @override
  State<LiveTalk> createState() => _LiveTalkState();
}

class _LiveTalkState extends State<LiveTalk> {
  Room? room;
  EventsListener<RoomEvent>? events;
  TranscriptionStreamReceiver? receiver;
  StreamSubscription<ReceivedMessage>? sub;
  final lines = <String, _Line>{};
  final scroll = ScrollController();
  String? phase; // null = not connected
  String agentState = '';
  bool muted = false;
  String? agentIdentity;
  Timer? _reopen;

  @override
  void didUpdateWidget(LiveTalk old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode && room != null) _end();
  }

  @override
  void dispose() {
    _end(update: false);
    scroll.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final s = context.read<AppState>();
    final v = s.voice;
    if (v == null) return s.toast('Live talk runs on the main computer.');
    if (!s.llmReady) return s.toast('Set up the AI first (Settings).');
    try {
      if (!v.ready) {
        setState(() => phase = 'Starting the voice engine…');
        await s.startVoice();
        if (!v.ready) {
          setState(() => phase = null);
          return s.toast(v.problem ?? 'The voice engine didn’t start. See Settings → Voice & hearing.');
        }
      }
      setState(() => phase = 'Connecting…');
      final id = Random().nextInt(1 << 32).toRadixString(36);
      final roomName = 'talk-${widget.mode}-${s.voiceLanguage}-$id';
      final token = await v.token(identity: 'you-$id', room: roomName, name: s.user?.name ?? 'You');
      final r = Room(roomOptions: const RoomOptions(defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, noiseSuppression: true, autoGainControl: true, stopAudioCaptureOnMute: false)));
      room = r;
      events = r.createListener()
        ..on<ParticipantAttributesChanged>((e) {
          final st = e.participant.attributes['lk.agent.state'];
          if (st == null || !mounted) return;
          agentIdentity = e.participant.identity;
          setState(() => agentState = st);
          _gateMic();
        })
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted && room == r) _end();
        });
      receiver = TranscriptionStreamReceiver(room: r);
      sub = receiver!.messages().listen((m) {
        final who = m.content is UserTranscript ? 'you' : 'ai';
        (lines[m.id] ??= _Line(who, '')).text = m.content.text;
        if (!mounted) return;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
        });
      });
      await r.connect(v.livekitUrl, token);
      await r.localParticipant?.setMicrophoneEnabled(true);
      _started = DateTime.now();
      _app = s;
      lines.clear();
      if (mounted) setState(() => phase = 'live');
    } catch (e) {
      await _end();
      s.toast('Couldn’t start the live conversation: $e');
    }
  }

  Future<void> _end({bool update = true}) async {
    _reopen?.cancel();
    final r = room;
    room = null;
    if (r != null && _app != null) unawaited(_save(_app!));
    await sub?.cancel();
    sub = null;
    await receiver?.dispose();
    receiver = null;
    await events?.dispose();
    events = null;
    if (r != null) {
      await r.disconnect();
      await r.dispose();
    }
    if (update && mounted) {
      setState(() {
        phase = null;
        agentState = '';
        muted = false;
      });
    }
  }

  DateTime? _started;
  AppState? _app; // kept so the conversation can be saved even while the page closes

  /// Each live conversation is kept in Calls (as a test call from this computer).
  Future<void> _save(AppState s) async {
    final convo = [for (final l in lines.values) if (l.text.trim().isNotEmpty) {'who': l.who, 'text': l.text}];
    if (convo.where((l) => l['who'] == 'you').isEmpty) return;
    final started = _started ?? DateTime.now();
    await s.db.insert('calls', {
      'direction': 'test',
      'name': widget.mode == 'caller' ? 'Live test call' : 'Live instructions',
      'number': '',
      'line': 'This computer · ${s.voiceLanguage}',
      'started_at': started.millisecondsSinceEpoch,
      'duration_s': DateTime.now().difference(started).inSeconds,
      'outcome': 'Test',
      'summary': convo.firstWhere((l) => l['who'] == 'you')['text'],
      'transcript': jsonEncode(convo),
    });
  }

  /// Ava can't hear herself through the speakers: the mic is off while she speaks and comes
  /// back a moment after (unless "Talk over Ava" is on, e.g. with headphones).
  void _gateMic() {
    final s = _app ?? context.read<AppState>();
    final p = room?.localParticipant;
    if (p == null || muted) return;
    _reopen?.cancel();
    if (agentState == 'speaking' && !s.voiceBargeIn) {
      p.setMicrophoneEnabled(false);
    } else {
      _reopen = Timer(const Duration(milliseconds: 350), () {
        if (room != null && !muted) room!.localParticipant?.setMicrophoneEnabled(true);
      });
    }
  }

  /// Stop Ava mid-sentence and listen.
  Future<void> _interrupt() async {
    final id = agentIdentity;
    if (room == null || id == null) return;
    try {
      await room!.localParticipant?.performRpc(PerformRpcParams(destinationIdentity: id, method: 'll.interrupt', payload: ''));
    } catch (_) {}
    _reopen?.cancel();
    if (!muted) await room?.localParticipant?.setMicrophoneEnabled(true);
  }

  Future<void> _mute() async {
    muted = !muted;
    await room?.localParticipant?.setMicrophoneEnabled(!muted);
    setState(() {});
  }

  /// The language whose voice is shown: the chosen one, or English when detecting.
  String _voiceLang(AppState s) => voiceOptions.containsKey(s.voiceLanguage) ? s.voiceLanguage : 'en';

  Map<String, String> _voiceItems(AppState s) {
    final lang = _voiceLang(s);
    return {for (final e in voiceOptions[lang]!.entries) e.key: s.voiceLanguage == 'auto' ? '${e.value} (English)' : e.value};
  }

  String _voiceValue(AppState s) {
    final lang = _voiceLang(s);
    final v = s.voiceChoice[lang];
    return v != null && voiceOptions[lang]!.containsKey(v) ? v : voiceOptions[lang]!.keys.first;
  }

  Widget _menu(BuildContext context, String value, Map<String, String> items, ValueChanged<String>? onChanged) => DropdownButton<String>(
    value: items.containsKey(value) ? value : items.keys.first,
    isDense: true,
    underline: const SizedBox(),
    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
    items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
    onChanged: onChanged == null ? null : (v) => v == null ? null : onChanged(v),
  );

  String get _status => switch ((phase, agentState)) {
    (null, _) => 'Tap to start a live conversation',
    ('live', 'speaking') => (_app?.voiceBargeIn ?? false) ? '${widget.name} is speaking — just talk to interrupt' : '${widget.name} is speaking — tap Interrupt to cut in',
    ('live', 'thinking') => '${widget.name} is thinking…',
    ('live', 'initializing' || '') => '${widget.name} is joining…',
    ('live', _) => muted ? 'Microphone off' : 'Listening — go ahead',
    (final p?, _) => p,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final live = phase == 'live';
    final busy = phase != null && !live;
    final speaking = live && agentState == 'speaking';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: live ? 'End conversation' : 'Start live conversation',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : (live ? _end : _begin),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live ? LL.red : LL.amber,
                        boxShadow: live
                            ? [
                                BoxShadow(
                                  color: LL.amber.withValues(alpha: speaking ? .45 : .2),
                                  spreadRadius: speaking ? 16 : 10,
                                ),
                              ]
                            : null,
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(36),
                              child: CircularProgressIndicator(strokeWidth: 3, color: LL.navy),
                            )
                          : Icon(live ? Icons.call_end_rounded : Icons.graphic_eq_rounded, size: 40, color: LL.navy),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Muted('Language'),
                  DropdownButton<String>(
                    value: voiceLanguages.containsKey(s.voiceLanguage) ? s.voiceLanguage : 'auto',
                    isDense: true,
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                    underline: const SizedBox(),
                    items: [for (final e in voiceLanguages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: live || busy ? null : (v) => s.setVoiceLanguage(v ?? 'auto'),
                  ),
                  if (live) Btn(muted ? 'Unmute' : 'Mute', small: true, kind: BtnKind.ghost, onPressed: _mute),
                  if (live && agentState == 'speaking') Btn('Interrupt', small: true, kind: BtnKind.amber, onPressed: _interrupt),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Muted('Voice'),
                  _menu(
                    context,
                    _voiceValue(s),
                    _voiceItems(s),
                    live || busy
                        ? null
                        : (v) {
                            final lang = voiceOptions.entries.firstWhere((e) => e.value.containsKey(v)).key;
                            s.setVoiceSetting('voice.$lang', v);
                          },
                  ),
                  const SizedBox(width: 6),
                  Muted('While thinking'),
                  _menu(context, s.thinkingSound, soundOptions, live || busy ? null : (v) => s.setVoiceSetting('thinking', v)),
                  const SizedBox(width: 6),
                  Muted('AI for other languages'),
                _menu(context, s.voiceOtherModel, {
                  '': 'Automatic${s.otherLanguageModel != null && s.voiceOtherModel.isEmpty ? ' (${s.otherLanguageModel})' : ''}',
                  for (final m in s.installedModels) m.name: m.name,
                  if (s.cloud != null) 'cloud': 'Cloud AI (best quality)',
                }, live || busy ? null : (v) => s.setVoiceSetting('otherModel', v)),
                const SizedBox(width: 6),
                Muted('Talk over ${widget.name}'),
                Transform.scale(
                  scale: .75,
                  child: Tooltip(
                    message: 'Interrupt ${widget.name} just by talking (she ignores her own voice). Turn off in a noisy room: then tap Interrupt.',
                    child: Switch(value: s.voiceBargeIn, onChanged: live || busy ? null : (v) => s.setVoiceSetting('bargeIn', v ? '1' : '0')),
                  ),
                ),
                const SizedBox(width: 6),
                Muted('Background'),
                  _menu(context, s.ambientSound, ambientOptions, live || busy ? null : (v) => s.setVoiceSetting('ambient', v)),
                ],
              ),
              if (s.voice != null && s.voice!.problem != null && !live) Padding(padding: const EdgeInsets.only(top: 8), child: Muted(s.voice!.problem!, size: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Live transcript',
          trailing: lines.isEmpty ? null : Btn('Clear', small: true, kind: BtnKind.ghost, onPressed: () => setState(lines.clear)),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380, minHeight: 80),
              child: lines.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Muted('What you say and what ${widget.name} says appears here as it’s spoken.'))
                  : ListView(
                      controller: scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(20),
                      children: [
                        for (final l in lines.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 62,
                                  child: Padding(padding: const EdgeInsets.only(top: 9), child: Eyebrow(l.who == 'ai' ? widget.name : 'You')),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(color: l.who == 'ai' ? c.amberSoft : c.canvas, borderRadius: BorderRadius.circular(LL.r)),
                                    child: SelectableText(l.text),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Voice engine status and install, for Settings.
class VoiceEnginePanel extends StatefulWidget {
  const VoiceEnginePanel({super.key});
  @override
  State<VoiceEnginePanel> createState() => _VoiceEnginePanelState();
}

class _VoiceEnginePanelState extends State<VoiceEnginePanel> {
  List<String>? missing;
  bool installing = false, phoneMissing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final v = context.read<AppState>().voice;
    if (v == null) return;
    final m = await v.missing();
    final noPhone = await v.sipBinary() == null;
    if (mounted) {
      setState(() {
        missing = m;
        phoneMissing = noPhone;
      });
    }
  }

  Future<void> _install() async {
    final s = context.read<AppState>();
    setState(() => installing = true);
    try {
      await s.installVoiceEngine();
      s.toast('Live voice is installed.');
    } catch (e) {
      s.toast('$e');
    } finally {
      if (mounted) setState(() => installing = false);
      _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final v = s.voice;
    if (v == null) return Muted('Live voice runs on the main computer.');
    String label(PartState st) => switch (st) {
      PartState.running => 'running',
      PartState.starting => 'starting…',
      PartState.failed => 'failed',
      PartState.missing => 'not installed',
      PartState.stopped => 'off',
    };
    const names = {EnginePart.redis: 'Phone link (Redis)', EnginePart.sip: 'Phone calls (SIP)', EnginePart.bridge: 'Incoming calls (Twilio sign-in)', EnginePart.gateway: 'Your own number (provider sign-in)', EnginePart.livekit: 'Live audio (LiveKit)', EnginePart.whisper: 'Hearing (Whisper)', EnginePart.accurate: 'Hearing, more languages', EnginePart.agent: 'Voice agent'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Muted('Live, hands-free conversations: the assistant hears you while you speak, answers the moment you stop, and you can interrupt it. Everything runs on this computer.'),
        const SizedBox(height: 12),
        for (final e in EnginePart.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Lamp(switch (v.state[e]!) {
                  PartState.running => LampState.on,
                  PartState.starting => LampState.ring,
                  PartState.failed => LampState.err,
                  _ => LampState.off,
                }),
                const SizedBox(width: 10),
                Expanded(child: Text(names[e]!)),
                Muted(label(v.state[e]!), mono: true, size: 12),
              ],
            ),
          ),
        if (missing != null && missing!.isNotEmpty) ...[const SizedBox(height: 8), Muted('Still needed: ${missing!.join(' · ')}', size: 12)],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (missing != null && missing!.any((m) => m.startsWith('the voice engine')))
              Btn(installing ? 'Installing…' : 'Install live voice', kind: BtnKind.primary, small: true, onPressed: installing ? null : _install),
            if (phoneMissing)
              Btn(installing ? 'Installing…' : 'Install phone calling', small: true, onPressed: installing ? null : () async {
                final app = context.read<AppState>();
                setState(() => installing = true);
                try {
                  await v.installPhone(patch: await rootBundle.loadString('assets/engine/livekit-sip-stun.patch'));
                  app.toast('Phone calling is installed. Restart live voice to use it.');
                } catch (e) {
                  app.toast('$e');
                } finally {
                  if (mounted) setState(() => installing = false);
                  _check();
                }
              }),
            if (v.ready) Btn('Stop', small: true, onPressed: v.stop) else Btn('Start', small: true, onPressed: missing?.isEmpty == true ? s.startVoice : null),
          ],
        ),
        if (installing || v.log.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            height: 120,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: context.c.canvas, borderRadius: BorderRadius.circular(LL.r)),
            child: SingleChildScrollView(reverse: true, child: Muted(v.log.takeLast(40).join('\n'), mono: true, size: 11)),
          ),
        ],
      ],
    );
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
