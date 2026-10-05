import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/catalog.dart';
import '../../services/hardware.dart';
import '../../services/ollama.dart';
import '../../services/system.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

Tone fitTone(Fit f) => switch (f) {
      Fit.great => Tone.green,
      Fit.fits => Tone.blue,
      Fit.tight => Tone.amber,
      Fit.tooLarge => Tone.red,
    };

/// Hearing / voice availability, checked once per screen.
class SpeechStatus {
  SpeechStatus(this.whisper, this.piper);
  final String? whisper, piper;
  static Future<SpeechStatus> check(AppState s) async =>
      SpeechStatus(await s.speech.whisperBinary(), await s.speech.piperBinary());
}

// ====================== Setup panel (wizard + Home) ======================

class EngineSetupPanel extends StatefulWidget {
  const EngineSetupPanel({super.key});
  @override
  State<EngineSetupPanel> createState() => _EngineSetupPanelState();
}

class _EngineSetupPanelState extends State<EngineSetupPanel> {
  SpeechStatus? sp;
  bool starting = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.refreshEngine();
    SpeechStatus.check(s).then((v) => mounted ? setState(() => sp = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hw = s.hardware;
    if (hw == null || !s.engineChecked) {
      return const Panel(child: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Checking this computer…')]));
    }
    final rec = s.catalog.recommend(hw);
    final binary = Ollama.findBinary();

    Widget thinking;
    if (s.ollamaVersion == null) {
      thinking = _row(
        'Thinking',
        binary == null ? 'Ollama is not installed' : 'Ollama is installed but not running',
        binary == null
            ? 'Ollama runs the language model. It’s free and open source.'
            : 'Start it to load a model.',
        LampState.off,
        [
          if (binary == null) Btn('Download Ollama', icon: Icons.download, kind: BtnKind.primary, small: true, onPressed: () => openExternal(Ollama.downloadUrl)),
          if (binary != null)
            Btn(starting ? 'Starting…' : 'Start Ollama', kind: BtnKind.primary, small: true, onPressed: starting ? null : () async {
              setState(() => starting = true);
              final ok = await s.ollama.start();
              await s.refreshEngine();
              if (mounted) setState(() => starting = false);
              if (!ok) s.toast('Ollama did not start. Open it from your Applications folder.');
            }),
          Btn('Check again', small: true, onPressed: s.refreshEngine),
        ],
      );
    } else {
      final hasRec = s.installedModels.any((m) => m.name == rec.id);
      final pulling = s.pulls.containsKey(rec.id);
      thinking = _row(
        'Thinking',
        s.llmReady ? s.llmModel! : 'No model downloaded yet',
        s.llmReady
            ? (s.llmModel == rec.id ? 'Recommended for this computer.' : 'Recommended here: ${rec.name} (${rec.sizeGb} GB).')
            : 'Recommended: ${rec.name} · ${rec.sizeGb} GB download.',
        s.llmReady ? LampState.on : LampState.off,
        [
          if (!hasRec)
            Btn(pulling ? 'Downloading…' : 'Download ${rec.name}', icon: Icons.download, kind: s.llmReady ? BtnKind.normal : BtnKind.primary, small: true,
                onPressed: pulling ? null : () => s.pullModel(rec.id)),
          if (hasRec && s.llmModel != rec.id) Btn('Use ${rec.name}', small: true, onPressed: () => s.setLlmModel(rec.id)),
        ],
        progress: pulling ? (s.pulls[rec.id] ?? 0) : null,
      );
    }

    final sttEntry = s.catalog.stt.firstWhere((e) => e.id == s.sttModel, orElse: () => s.catalog.stt.first);
    final sttPath = s.speech.sttModelPath(sttEntry.id);
    final hearing = sp == null
        ? _row('Hearing', 'Checking…', '', LampState.off, const [])
        : _row(
            'Hearing',
            sp!.whisper == null ? 'whisper.cpp is not installed' : sttPath == null ? sttEntry.name : '${sttEntry.name} · ready',
            sp!.whisper == null
                ? 'Needed to understand speech. Typing to Ava still works without it.'
                : sttPath == null
                    ? '${sttEntry.sizeMb} MB download.'
                    : 'Runs on this computer.',
            sp!.whisper != null && sttPath != null ? LampState.on : LampState.off,
            [
              if (sp!.whisper == null) Btn('How to install', small: true, onPressed: () => openExternal('https://github.com/ggml-org/whisper.cpp#quick-start')),
              if (sp!.whisper != null && sttPath == null)
                Btn(s.speechDownloads.containsKey(sttEntry.id) ? 'Downloading…' : 'Download', icon: Icons.download, small: true,
                    onPressed: s.speechDownloads.containsKey(sttEntry.id) ? null : () => s.downloadSpeech(sttEntry, tts: false)),
            ],
            progress: s.speechDownloads[sttEntry.id],
          );

    final ttsEntry = s.catalog.tts.firstWhere((e) => e.id == s.ttsVoice, orElse: () => s.catalog.tts.first);
    final voicePath = s.speech.ttsVoicePath(ttsEntry.id);
    final voice = sp == null
        ? _row('Voice', 'Checking…', '', LampState.off, const [])
        : _row(
            'Voice',
            sp!.piper != null && voicePath != null ? '${ttsEntry.name} · ready' : 'Built-in computer voice',
            sp!.piper == null
                ? 'Works now. Install Piper for more natural voices.'
                : voicePath == null
                    ? 'Download ${ttsEntry.name} (${ttsEntry.sizeMb} MB) for a natural voice.'
                    : 'Piper · runs on this computer.',
            LampState.on,
            [
              if (sp!.piper != null && voicePath == null)
                Btn(s.speechDownloads.containsKey(ttsEntry.id) ? 'Downloading…' : 'Download voice', icon: Icons.download, small: true,
                    onPressed: s.speechDownloads.containsKey(ttsEntry.id) ? null : () => s.downloadSpeech(ttsEntry, tts: true)),
            ],
            progress: s.speechDownloads[ttsEntry.id],
          );

    return Column(children: [
      Panel(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('This computer'),
              const SizedBox(height: 4),
              Text('${hw.cpu} · ${hw.ramGb.toStringAsFixed(0)} GB memory', style: const TextStyle(fontWeight: FontWeight.w600)),
              Muted('${hw.os} · ${hw.accel}'),
            ]),
          ),
          Pill(rec.params >= 8 ? 'Great for AI' : rec.params >= 3 ? 'Good for AI' : 'Light AI only',
              tone: rec.params >= 3 ? Tone.green : Tone.amber),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(padding: EdgeInsets.zero, child: Column(children: [thinking, hearing, voice])),
    ]);
  }

  Widget _row(String label, String title, String sub, LampState lamp, List<Widget> actions, {double? progress}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(border: label == 'Voice' ? null : Border(bottom: BorderSide(color: context.c.line))),
        child: Row(children: [
          SizedBox(width: 84, child: Muted(label, size: 13)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Lamp(lamp), const SizedBox(width: 8), Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)))]),
              if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 16, top: 2), child: Muted(sub)),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8, right: 20),
                  child: Row(children: [Expanded(child: Meter(progress, color: LL.amber)), const SizedBox(width: 10), Mono('${(progress * 100).toStringAsFixed(0)}%', size: 11.5)]),
                ),
            ]),
          ),
          Wrap(spacing: 6, children: actions),
        ]),
      );
}

// ====================== Language models ======================

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});
  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  List<EngineStatus> others = [];
  String filter = 'fits';
  final busy = <String>{};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.refreshEngine();
    Future.wait([detectLlamaCpp(), detectLmStudio()]).then((v) {
      if (mounted) setState(() => others = [...v, detectVllm()]);
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => s.refreshEngine());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _act(String id, Future<void> Function() f, String done) async {
    final s = context.read<AppState>();
    setState(() => busy.add(id));
    try {
      await f();
      await s.log(done);
      s.toast(done);
    } catch (e) {
      s.toast('$e');
    } finally {
      await s.refreshEngine();
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hw = s.hardware;
    final running = s.ollamaVersion != null;
    final totalLoaded = s.loadedModels.fold<int>(0, (a, m) => a + m.sizeBytes) / 1e9;

    final runtimes = [
      EngineStatus('Ollama', running ? 'v${s.ollamaVersion} · running · port 11434' : Ollama.findBinary() == null ? 'Not installed' : 'Installed · not running',
          running ? EngineState.running : Ollama.findBinary() == null ? EngineState.missing : EngineState.installed),
      ...others,
    ];

    final catalog = s.catalog.llm.where((m) {
      final installed = s.installedModels.any((i) => i.name == m.id);
      if (filter == 'downloaded') return installed;
      if (filter == 'fits' && hw != null) return m.fitFor(hw) != Fit.tooLarge;
      return true;
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('Language models',
          description: 'The engine runs models; the model does the thinking. Sizes are checked against this computer.',
          actions: [Btn('Refresh', icon: Icons.refresh, onPressed: s.refreshEngine)]),
      Text('Engine', style: displayStyle(context, 17)),
      const SizedBox(height: 10),
      Grid(cols: 4, children: [
        for (final r in runtimes)
          Panel(
            borderColor: r.name == 'Ollama' && running ? LL.navy3 : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                Lamp(r.state == EngineState.running ? LampState.on : LampState.off),
              ]),
              const SizedBox(height: 4),
              Muted(r.detail),
              const SizedBox(height: 12),
              if (r.name == 'Ollama' && !running)
                Btn(Ollama.findBinary() == null ? 'Download' : 'Start', small: true, kind: BtnKind.primary,
                    onPressed: () async {
                      if (Ollama.findBinary() == null) {
                        await openExternal(Ollama.downloadUrl);
                      } else {
                        await s.ollama.start();
                        await s.refreshEngine();
                      }
                    })
              else if (r.name == 'Ollama')
                const Pill('In use', tone: Tone.amber)
              else if (r.state == EngineState.missing && r.name == 'LM Studio')
                Btn('Download', small: true, onPressed: () => openExternal('https://lmstudio.ai/download'))
              else if (r.state == EngineState.missing && r.name == 'llama.cpp')
                Btn('Download', small: true, onPressed: () => openExternal('https://github.com/ggml-org/llama.cpp/releases'))
              else
                Pill(r.state == EngineState.unsupported ? 'Not available here' : 'Coming soon'),
            ]),
          ),
      ]),
      const SizedBox(height: 22),
      Section(
        title: 'Loaded now',
        trailing: Muted('Using ${totalLoaded.toStringAsFixed(1)} GB${hw == null ? '' : ' of ${hw.ramGb.toStringAsFixed(0)} GB'}', mono: true),
        children: [
          if (s.loadedModels.isEmpty)
            const EmptyState(icon: Icons.memory, title: 'No model in memory', body: 'Load one below. Talk to Ava loads the chosen model automatically.'),
          for (final m in s.loadedModels)
            Tile(
              last: m == s.loadedModels.last,
              leading: LogoBox(child: Text(m.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700))),
              title: Row(children: [
                Text(m.name),
                const SizedBox(width: 8),
                if (m.name == s.llmModel) const Pill('Used for calls', tone: Tone.amber),
              ]),
              subtitle: Muted('${(m.sizeBytes / 1e9).toStringAsFixed(1)} GB · ${m.vramBytes > 0 ? 'GPU' : 'CPU'}', mono: true),
              trailing: Btn(busy.contains(m.name) ? 'Unloading…' : 'Unload', icon: Icons.stop, small: true,
                  onPressed: busy.contains(m.name) ? null : () => _act(m.name, () => s.ollama.unload(m.name), 'Unloaded ${m.name}')),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Section(
        title: 'Models',
        trailing: Segmented(value: filter, options: const {'fits': 'Fits this computer', 'all': 'All', 'downloaded': 'Downloaded'}, onChanged: (v) => setState(() => filter = v)),
        children: [
          if (!running) const EmptyState(icon: Icons.power_off_outlined, title: 'Ollama isn’t running', body: 'Start it above to download and load models.'),
          if (running)
            for (final m in [
              ...catalog,
              // Installed models that aren't in our catalog still show up.
              if (filter != 'fits')
                for (final i in s.installedModels.where((i) => !s.catalog.llm.any((c) => c.id == i.name)))
                  LlmEntry(i.name, i.name, double.parse(i.sizeGb.toStringAsFixed(1)), 0, 'Downloaded · ${i.params} ${i.quant}'),
            ])
              _modelTile(s, hw, m),
        ],
      ),
    ]);
  }

  Widget _modelTile(AppState s, Hardware? hw, LlmEntry m) {
    final installed = s.installedModels.any((i) => i.name == m.id);
    final loaded = s.loadedModels.any((l) => l.name == m.id);
    final fit = hw == null || m.params == 0 ? null : m.fitFor(hw);
    final pulling = s.pulls.containsKey(m.id);
    return Tile(
      title: Row(children: [
        Flexible(child: Text(m.name)),
        const SizedBox(width: 8),
        Muted('${m.sizeGb} GB', mono: true),
        const SizedBox(width: 8),
        if (fit != null) Pill(fit.label, tone: fitTone(fit)),
        if (m.id == s.llmModel) ...[const SizedBox(width: 6), const Pill('Used for calls', tone: Tone.amber)],
      ]),
      subtitle: pulling
          ? Padding(padding: const EdgeInsets.only(top: 6, right: 40), child: Meter(s.pulls[m.id] ?? 0, color: LL.amber))
          : Muted(m.note),
      trailing: Wrap(spacing: 6, children: [
        if (!installed)
          Btn(pulling ? '${((s.pulls[m.id] ?? 0) * 100).toStringAsFixed(0)}%' : 'Download', icon: Icons.download, small: true,
              onPressed: pulling || fit == Fit.tooLarge ? null : () => s.pullModel(m.id)),
        if (installed && m.id != s.llmModel) Btn('Use for calls', small: true, onPressed: () => s.setLlmModel(m.id)),
        if (installed && !loaded)
          Btn(busy.contains(m.id) ? 'Loading…' : 'Load', icon: Icons.play_arrow, small: true, kind: BtnKind.primary,
              onPressed: busy.contains(m.id) ? null : () => _act(m.id, () => s.ollama.load(m.id), 'Loaded ${m.id}')),
        if (loaded)
          Btn('Unload', icon: Icons.stop, small: true, onPressed: busy.contains(m.id) ? null : () => _act(m.id, () => s.ollama.unload(m.id), 'Unloaded ${m.id}')),
        if (installed)
          Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
            final ok = await confirm(context, 'Delete ${m.name}?', 'This frees ${m.sizeGb} GB. You can download it again later.', 'Delete');
            if (ok) await _act(m.id, () => s.ollama.delete(m.id), 'Deleted ${m.id}');
          }),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: displayStyle(c, 20)),
        content: Text(body),
        actions: [
          Btn('Cancel', onPressed: () => Navigator.pop(c, false)),
          Btn(action, kind: BtnKind.danger, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ) ??
    false;

// ====================== Voice & hearing ======================

class SpeechPage extends StatefulWidget {
  const SpeechPage({super.key});
  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  SpeechStatus? sp;
  final sample = TextEditingController(text: 'Hi, you’ve reached the line. How can I help?');

  @override
  void initState() {
    super.initState();
    SpeechStatus.check(context.read<AppState>()).then((v) => mounted ? setState(() => sp = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead('Voice & hearing', description: 'Hearing turns the caller’s speech into text. Voice speaks the reply. Both run on this computer.'),
      Grid(cols: 2, children: [
        Section(
          title: 'Hearing',
          trailing: sp == null
              ? null
              : Pill(sp!.whisper == null ? 'whisper.cpp missing' : 'whisper.cpp found', tone: sp!.whisper == null ? Tone.red : Tone.green),
          children: [
            for (final e in s.catalog.stt) _speechTile(s, e, tts: false, last: e == s.catalog.stt.last),
          ],
        ),
        Section(
          title: 'Voices',
          trailing: sp == null ? null : Pill(sp!.piper == null ? 'Piper missing · using built-in voice' : 'Piper found', tone: sp!.piper == null ? Tone.amber : Tone.green),
          children: [
            for (final e in s.catalog.tts) _speechTile(s, e, tts: true),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Field(
                label: 'Hear any sentence',
                child: Row(children: [
                  Expanded(child: TextField(controller: sample)),
                  const SizedBox(width: 8),
                  Btn('Speak', icon: Icons.volume_up_outlined, kind: BtnKind.primary, onPressed: () {
                    s.speech.speak(sample.text, voicePath: s.speech.ttsVoicePath(s.ttsVoice));
                  }),
                ]),
              ),
            ),
          ],
        ),
      ]),
      const SizedBox(height: 16),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Coming next', style: displayStyle(context, 16)),
          const SizedBox(height: 6),
          const Muted('Parakeet (fast multilingual hearing), Kokoro voices, streaming speech and phone-quality (8 kHz) tuning arrive with the call engine.'),
        ]),
      ),
    ]);
  }

  Widget _speechTile(AppState s, SpeechEntry e, {required bool tts, bool last = false}) {
    final have = tts ? s.speech.ttsVoicePath(e.id) != null : s.speech.sttModelPath(e.id) != null;
    final chosen = tts ? s.ttsVoice == e.id : s.sttModel == e.id;
    final dl = s.speechDownloads[e.id];
    return Tile(
      last: last,
      leading: LogoBox(child: Icon(tts ? Icons.record_voice_over_outlined : Icons.hearing)),
      title: Row(children: [Flexible(child: Text(e.name)), const SizedBox(width: 8), Muted('${e.sizeMb} MB', mono: true)]),
      subtitle: dl != null ? Padding(padding: const EdgeInsets.only(top: 6, right: 30), child: Meter(dl, color: LL.amber)) : Muted(e.note),
      trailing: Wrap(spacing: 6, children: [
        if (have && chosen) const Pill('In use', tone: Tone.amber),
        if (have && !chosen) Btn('Use', small: true, onPressed: () => tts ? s.setTtsVoice(e.id) : s.setSttModel(e.id)),
        if (!have)
          Btn(dl != null ? '${(dl * 100).toStringAsFixed(0)}%' : 'Download', icon: Icons.download, small: true,
              onPressed: dl != null ? null : () => s.downloadSpeech(e, tts: tts)),
      ]),
    );
  }
}

// ====================== This computer ======================

class HardwarePage extends StatelessWidget {
  const HardwarePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hw = s.hardware;
    if (hw == null) return const Center(child: CircularProgressIndicator());
    final rec = s.catalog.recommend(hw);
    Widget stat(String k, String v, String sub) => Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(k),
          const SizedBox(height: 6),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          Muted(sub),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead('This computer', description: 'What LocalAILine found, and what it recommends.', actions: [
        Btn('Scan again', icon: Icons.refresh, onPressed: () async {
          s.hardware = await Hardware.detect();
          s.refresh();
          s.toast('Scan finished.');
        }),
      ]),
      Grid(cols: 4, children: [
        stat('Processor', hw.cpu, '${hw.cores} cores'),
        stat('Memory', '${hw.ramGb.toStringAsFixed(0)} GB', hw.unifiedMemory ? 'Unified (shared with GPU)' : 'System RAM'),
        stat('Graphics', hw.gpu, hw.accel),
        stat('Free disk', '${hw.freeDiskGb.toStringAsFixed(0)} GB', hw.os),
      ]),
      const SizedBox(height: 16),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Recommended'),
          const SizedBox(height: 4),
          Text('${rec.name} for thinking', style: displayStyle(context, 20)),
          const SizedBox(height: 4),
          Muted('Models may use up to ${hw.modelBudgetGb.toStringAsFixed(1)} GB here, keeping room for hearing and voice.'),
        ]),
      ),
    ]);
  }
}
