import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/catalog.dart';
import '../../services/cloud_llm.dart';
import '../../services/hardware.dart';
import '../../services/ollama.dart';
import '../../services/system.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'live_talk.dart';

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
  bool _pickCloud = false;

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
      final entry = s.catalog.llm.where((m) => m.id == s.llmModel).firstOrNull;
      thinking = _row(
        'Thinking',
        s.llmReady ? (entry?.name ?? s.llmModel!) : 'Choose a model below',
        s.llmReady
            ? (s.llmModel == rec.id ? 'Best for this computer · downloaded' : 'Downloaded · best here: ${rec.name}')
            : 'Pick one to download. We marked the best for this computer.',
        s.llmReady ? LampState.on : LampState.off,
        const [],
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

    final source = Align(
      alignment: Alignment.centerLeft,
      child: Segmented(
        value: s.llmSource,
        options: const {'local': 'On this computer · private', 'cloud': 'Cloud AI · OpenAI, Azure, Google, Claude'},
        onChanged: (v) => v == 'cloud' && s.cloud == null ? setState(() => _pickCloud = true) : s.setLlmSource(v),
      ),
    );
    if (s.usingCloud || _pickCloud) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        source,
        const SizedBox(height: 12),
        CloudPanel(onCancel: () => setState(() => _pickCloud = false), onSaved: () => setState(() => _pickCloud = false)),
        const SizedBox(height: 12),
        Panel(padding: EdgeInsets.zero, child: Column(children: [hearing, voice])),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      source,
      const SizedBox(height: 12),
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
      if (s.ollamaVersion != null) ...[const SizedBox(height: 12), const ModelPicker()],
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

// ====================== Cloud AI ======================

/// Pick a provider, paste the key, Test, Use. That's it.
class CloudPanel extends StatefulWidget {
  const CloudPanel({super.key, this.onCancel, this.onSaved});
  final VoidCallback? onCancel, onSaved;
  @override
  State<CloudPanel> createState() => _CloudPanelState();
}

class _CloudPanelState extends State<CloudPanel> {
  late CloudProvider provider;
  final key = TextEditingController();
  final endpoint = TextEditingController();
  final deployment = TextEditingController();
  List<String> models = [];
  String? model, result;
  bool testing = false, ok = false, editing = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppState>().cloud;
    provider = c?.provider ?? CloudProvider.openai;
    if (c != null) {
      key.text = c.apiKey;
      endpoint.text = c.endpoint;
      deployment.text = c.provider == CloudProvider.azure ? c.model : '';
      model = c.model;
    }
    editing = c == null;
  }

  CloudConfig get _config => CloudConfig(
        provider: provider,
        apiKey: key.text.trim(),
        endpoint: endpoint.text.trim(),
        model: provider == CloudProvider.azure ? deployment.text.trim() : (model ?? ''),
      );

  Future<void> _test() async {
    setState(() {
      testing = true;
      result = null;
      ok = false;
    });
    try {
      final list = await context.read<AppState>().cloudLlm.test(_config);
      setState(() {
        models = list;
        model = list.isEmpty ? null : list.first;
        ok = list.isNotEmpty;
        result = list.isEmpty ? 'Connected, but no chat models were found on this account.' : 'Connected. Choose a model and press Use.';
      });
    } catch (e) {
      setState(() => result = '$e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> _use() async {
    final s = context.read<AppState>();
    await s.saveCloud(_config);
    s.toast('Ava now thinks with ${provider.label}.');
    setState(() => editing = false);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!editing && s.cloud != null) {
      return Panel(
        child: Row(children: [
          const Lamp(LampState.on),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.cloud!.provider.label} · ${s.cloud!.model}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Muted('Connected. Calls and chats are sent to ${s.cloud!.provider.label}.'),
            ]),
          ),
          Btn('Change', small: true, onPressed: () => setState(() => editing = true)),
          const SizedBox(width: 6),
          Btn('Disconnect', small: true, kind: BtnKind.ghost, onPressed: () async {
            await s.removeCloud();
            widget.onCancel?.call();
          }),
        ]),
      );
    }
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Connect a cloud AI', style: displayStyle(context, 17)),
        const SizedBox(height: 4),
        const Muted('Ava thinks with the provider you choose. Hearing and voice still run on this computer.'),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in CloudProvider.values)
            ChoiceChip(
              label: Text(p.label),
              selected: provider == p,
              onSelected: (_) => setState(() {
                provider = p;
                models = [];
                model = null;
                ok = false;
                result = null;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Field(
          label: 'API key',
          hint: '${provider.keyHint}. Saved on this computer only.',
          child: TextField(controller: key, obscureText: true, onSubmitted: (_) => _test()),
        ),
        if (provider == CloudProvider.azure) ...[
          const SizedBox(height: 12),
          Grid(cols: 2, children: [
            Field(label: 'Endpoint', child: TextField(controller: endpoint, decoration: const InputDecoration(hintText: 'https://my-resource.openai.azure.com'))),
            Field(label: 'Deployment name', child: TextField(controller: deployment, decoration: const InputDecoration(hintText: 'gpt-4o-mini'))),
          ]),
        ],
        if (models.length > 1 && provider != CloudProvider.azure) ...[
          const SizedBox(height: 12),
          Field(label: 'Model', child: Dropdown(value: model ?? models.first, items: {for (final m in models) m: m}, onChanged: (v) => setState(() => model = v))),
        ],
        if (result != null) ...[
          const SizedBox(height: 10),
          Text(result!, style: TextStyle(color: ok ? LL.green : LL.red, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Btn(testing ? 'Testing…' : 'Test', icon: Icons.bolt_outlined, onPressed: testing ? null : _test),
          const SizedBox(width: 8),
          Btn('Use', kind: BtnKind.primary, onPressed: ok ? _use : null),
          const Spacer(),
          if (widget.onCancel != null) Btn('Cancel', kind: BtnKind.ghost, onPressed: () {
            if (s.cloud != null) {
              setState(() => editing = false);
            } else {
              widget.onCancel!();
            }
          }),
        ]),
      ]),
    );
  }
}

// ====================== Model picker ======================

/// The best few models for this computer plus everything already downloaded.
/// Tap one to use it; download it first if needed.
class ModelPicker extends StatelessWidget {
  const ModelPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hw = s.hardware;
    if (hw == null) return const SizedBox();
    final installed = s.installedModels.map((m) => m.name).toSet();
    final choices = s.catalog.choices(hw);
    final shown = choices.map((c) => c.$1.id).toSet();
    final others = s.installedModels.where((m) => !shown.contains(m.name)).toList();

    Widget row(String id, String name, String size, String label, Fit? fit, {bool last = false}) {
      final have = installed.contains(id);
      final selected = s.llmModel == id && have;
      final pulling = s.pulls.containsKey(id);
      return Tile(
        last: last,
        onTap: have && !selected ? () => s.setLlmModel(id, manual: true) : null,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? LL.green : context.c.muted, size: 20),
        title: Row(children: [
          Flexible(child: Text(name)),
          const SizedBox(width: 8),
          Muted(size, mono: true),
          const SizedBox(width: 8),
          if (label.isNotEmpty) Pill(label, tone: label.startsWith('Best') ? Tone.amber : Tone.neutral),
        ]),
        subtitle: pulling
            ? Padding(padding: const EdgeInsets.only(top: 6, right: 30), child: Meter(s.pulls[id] ?? 0, color: LL.amber))
            : Muted(have ? (selected ? 'Downloaded · in use' : 'Downloaded · tap to use') : 'Not downloaded'),
        trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (fit != null) Pill(fit.label, tone: fitTone(fit)),
          if (!have)
            Btn(pulling ? '${((s.pulls[id] ?? 0) * 100).toStringAsFixed(0)}%' : 'Download', icon: Icons.download, small: true,
                kind: label.startsWith('Best') ? BtnKind.primary : BtnKind.normal, onPressed: pulling ? null : () => s.pullModel(id)),
          if (have && !selected) Btn('Use', small: true, onPressed: () => s.setLlmModel(id, manual: true)),
        ]),
      );
    }

    final rows = [
      for (final (m, label) in choices) (m.id, m.name, '${m.sizeGb} GB', label, m.fitFor(hw)),
      for (final o in others)
        (o.name, s.catalog.llm.where((c) => c.id == o.name).firstOrNull?.name ?? o.name, '${o.sizeGb.toStringAsFixed(1)} GB', 'Downloaded earlier',
            s.catalog.llm.where((c) => c.id == o.name).firstOrNull?.fitFor(hw)),
    ];
    return Section(
      title: 'Choose the thinking model',
      trailing: Muted('Up to ${hw.modelBudgetGb.toStringAsFixed(0)} GB fits here', mono: true),
      children: [for (var i = 0; i < rows.length; i++) row(rows[i].$1, rows[i].$2, rows[i].$3, rows[i].$4, rows[i].$5, last: i == rows.length - 1)],
    );
  }
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
        if (installed && m.id != s.llmModel) Btn('Use for calls', small: true, onPressed: () => s.setLlmModel(m.id, manual: true)),
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
      const Section(title: 'Live conversations', children: [Padding(padding: EdgeInsets.all(20), child: VoiceEnginePanel())]),
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
