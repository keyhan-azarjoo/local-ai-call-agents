import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../services/ollama.dart';
import '../../services/speech.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

enum TalkMode { caller, owner }

class _Turn {
  _Turn(this.who, this.text, {this.meta});
  final String who; // ai | you
  String text;
  String? meta;
  Map<String, dynamic>? task;
}

/// Talk to the assistant from this computer — as a caller would, or as the
/// owner giving instructions (e.g. "call the dentist and move my appointment").
class TalkPage extends StatefulWidget {
  const TalkPage({super.key});
  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  TalkMode mode = TalkMode.caller;
  final turns = <_Turn>[];
  final history = <ChatMessage>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  Map<String, Object?>? agent;
  bool listening = false, thinking = false, saved = false;
  late bool voiceOn = context.read<AppState>().speakReplies;
  String? status;

  late final Speech _speech;

  @override
  void initState() {
    super.initState();
    _speech = context.read<AppState>().speech;
    _start();
  }

  @override
  void dispose() {
    recorder.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final s = context.read<AppState>();
    final agents = await s.db.all('agents', where: "handles = 'incoming'", orderBy: 'id');
    agent = agents.isEmpty ? null : agents.first;
    final name = (agent?['name'] as String?) ?? 'Ava';
    final owner = s.user?.name.split(' ').first ?? 'the owner';
    turns.clear();
    history.clear();
    saved = false;
    if (mode == TalkMode.caller) {
      history.add(ChatMessage('system',
          '${agent?['instructions'] ?? ''}\nYour name is $name. You are on a phone call with a caller. Reply in ${agent?['language'] ?? 'English'}. Keep replies short and spoken — no lists, no markdown.'));
      final greeting = (agent?['greeting'] as String?) ?? 'Hello, how can I help?';
      history.add(ChatMessage('assistant', greeting));
      turns.add(_Turn('ai', greeting, meta: 'greeting'));
      if (voiceOn) _say(greeting);
    } else {
      history.add(ChatMessage('system',
          'You are $name, the personal AI phone assistant of $owner inside the LocalAILine app. $owner is talking to you directly. '
          'Be brief and helpful. You can make phone calls for $owner. When $owner asks you to call someone, reply with one short confirmation '
          'sentence, then on the last line write exactly: CALL_TASK {"to": "<who>", "number": "<phone number or empty>", "goal": "<what to achieve>"}. '
          'Never write CALL_TASK unless asked to make a call.'));
      turns.add(_Turn('ai', 'Hi $owner. What would you like me to do? For example: “Call Riverside Dental and move my check-up to next week.”'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _say(String text) async {
    final s = context.read<AppState>();
    await s.speech.speak(text, voicePath: s.speech.ttsVoicePath(s.ttsVoice));
  }

  Future<void> _send(String text) async {
    final s = context.read<AppState>();
    text = text.trim();
    if (text.isEmpty || thinking) return;
    if (!s.llmReady) {
      s.toast('Set up the AI first (Settings).');
      return;
    }
    input.clear();
    await s.speech.stop();
    history.add(ChatMessage('user', text));
    final reply = _Turn('ai', '');
    setState(() {
      turns.add(_Turn('you', text));
      turns.add(reply);
      thinking = true;
      status = 'Thinking…';
    });
    _scrollDown();
    final t0 = DateTime.now();
    Duration? first;
    final buf = StringBuffer();
    try {
      await for (final piece in s.chat(history)) {
        first ??= DateTime.now().difference(t0);
        buf.write(piece);
        reply.text = _visible(buf.toString());
        setState(() {});
        _scrollDown();
      }
      final full = buf.toString();
      history.add(ChatMessage('assistant', full));
      reply.text = _visible(full);
      reply.task = _task(full);
      reply.meta = '${((first ?? Duration.zero).inMilliseconds / 1000).toStringAsFixed(2)} s to first word · ${s.llmLabel}';
      if (voiceOn) _say(reply.text);
    } catch (e) {
      reply.text = 'I couldn’t reply: $e';
    } finally {
      if (mounted) {
        setState(() {
          thinking = false;
          status = null;
        });
      }
    }
  }

  String _visible(String t) => t.split('\n').where((l) => !l.trim().startsWith('CALL_TASK')).join('\n').trim();

  Map<String, dynamic>? _task(String t) {
    final m = RegExp(r'CALL_TASK\s*(\{.*\})').firstMatch(t);
    if (m == null) return null;
    try {
      return jsonDecode(m.group(1)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      });

  Future<void> _toggleMic() async {
    final s = context.read<AppState>();
    if (listening) {
      final path = await recorder.stop();
      setState(() {
        listening = false;
        status = 'Understanding…';
      });
      if (path == null) return setState(() => status = null);
      final model = s.speech.sttModelPath(s.sttModel);
      if (model == null) {
        setState(() => status = null);
        s.toast('Download a hearing model first (Voice & hearing).');
        return;
      }
      try {
        final lang = (agent?['language'] as String?) == 'English' ? 'en' : 'auto';
        final text = await s.speech.transcribe(path, modelPath: model, language: s.sttModel.contains('.en') ? 'en' : lang);
        setState(() => status = null);
        if (text.isEmpty) {
          s.toast('I didn’t catch that. Try again a little closer to the microphone.');
        } else {
          await _send(text);
        }
      } catch (e) {
        setState(() => status = null);
        s.toast('$e');
      }
      return;
    }
    if (await s.speech.whisperBinary() == null) {
      s.toast('Hearing needs whisper.cpp. You can still type below.');
      return;
    }
    if (!await recorder.hasPermission()) {
      s.toast('Microphone access was refused. Allow it in System Settings → Privacy → Microphone.');
      return;
    }
    await s.speech.stop();
    final path = p.join(Directory.systemTemp.path, 'll_mic_${DateTime.now().millisecondsSinceEpoch}.wav');
    await recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    setState(() => listening = true);
  }

  Future<void> _createTask(Map<String, dynamic> t) async {
    final s = context.read<AppState>();
    await s.db.insert('call_tasks', {
      'to_name': t['to']?.toString(),
      'number': (t['number']?.toString() ?? '').trim(),
      'goal': t['goal']?.toString() ?? '',
      'status': 'draft',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await s.log('Drafted a call to ${t['to']} from Talk');
    s.go(PageId.outbound);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final convo = turns.map((t) => {'who': t.who, 'text': t.text}).toList();
    await s.db.insert('calls', {
      'direction': 'test',
      'name': 'Test call from this computer',
      'number': '',
      'line': 'This computer',
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'duration_s': 0,
      'outcome': 'Test',
      'summary': turns.where((t) => t.who == 'you').map((t) => t.text).take(1).join(),
      'transcript': jsonEncode(convo),
    });
    setState(() => saved = true);
    s.toast('Saved to Calls.');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final name = (agent?['name'] as String?) ?? 'Ava';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(children: [
          Text('Talk to $name', style: displayStyle(context, 30)),
          const SizedBox(height: 6),
          Muted('Uses your microphone and speakers. Nothing leaves this computer.', size: 14),
          const SizedBox(height: 14),
          Segmented(
            value: mode,
            options: const {TalkMode.caller: 'Pretend I’m a caller', TalkMode.owner: 'Give instructions'},
            onChanged: (m) {
              setState(() => mode = m);
              _start();
            },
          ),
          const SizedBox(height: 8),
          Muted(mode == TalkMode.caller
              ? '$name answers exactly as on a real call — same greeting and instructions.'
              : 'Ask $name to make calls for you, or anything else.'),
          const SizedBox(height: 18),
          if (!s.llmReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Panel(
                borderColor: LL.amber,
                child: Row(children: [
                  const Icon(Icons.info_outline, color: LL.amber),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('The AI isn’t set up yet. Choose a local model or connect a cloud AI.')),
                  Btn('Set up AI', kind: BtnKind.primary, small: true, onPressed: () => s.go(PageId.settings)),
                ]),
              ),
            ),
          Panel(
            padding: const EdgeInsets.all(26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Semantics(
                button: true,
                label: listening ? 'Stop talking' : 'Start talking',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: thinking ? null : _toggleMic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listening ? LL.red : LL.amber,
                      boxShadow: listening ? [BoxShadow(color: LL.amber.withValues(alpha: .25), spreadRadius: 12)] : null,
                    ),
                    child: Icon(listening ? Icons.stop_rounded : Icons.mic_none_rounded, size: 40, color: LL.navy),
                  ),
                ),
              )),
              const SizedBox(height: 14),
              Text(status ?? (listening ? 'Listening… tap to send' : 'Tap to talk'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Muted('Speak replies'),
                Transform.scale(scale: .75, child: Switch(value: voiceOn, onChanged: (v) {
                  setState(() => voiceOn = v);
                  s.speakReplies = v;
                  if (!v) s.speech.stop();
                })),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Section(
            title: 'Conversation',
            trailing: Wrap(spacing: 6, children: [
              if (mode == TalkMode.caller && turns.length > 1)
                Btn(saved ? 'Saved' : 'Save to Calls', small: true, onPressed: saved ? null : _save),
              Btn('Start over', small: true, kind: BtnKind.ghost, onPressed: _start),
            ]),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView(
                  controller: scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final t in turns)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 62, child: Padding(padding: const EdgeInsets.only(top: 9), child: Eyebrow(t.who == 'ai' ? name : 'You'))),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(color: t.who == 'ai' ? c.amberSoft : c.canvas, borderRadius: BorderRadius.circular(LL.r)),
                                child: t.text.isEmpty ? const SizedBox(height: 16, width: 16, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))) : SelectableText(t.text),
                              ),
                              if (t.meta != null) Padding(padding: const EdgeInsets.only(top: 3), child: Muted(t.meta!, mono: true, size: 11)),
                              if (t.task != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Panel(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(children: [
                                      const Icon(Icons.phone_forwarded_outlined, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('Call ${t.task!['to'] ?? ''}: ${t.task!['goal'] ?? ''}', style: const TextStyle(fontSize: 13))),
                                      Btn('Review call', kind: BtnKind.amber, small: true, onPressed: () => _createTask(t.task!)),
                                    ]),
                                  ),
                                ),
                            ]),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(children: [
                  Expanded(child: TextField(controller: input, onSubmitted: _send, decoration: const InputDecoration(hintText: 'Or type a message…'))),
                  const SizedBox(width: 8),
                  Btn('Send', kind: BtnKind.primary, onPressed: thinking ? null : () => _send(input.text)),
                ]),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
