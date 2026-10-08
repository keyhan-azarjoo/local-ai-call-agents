import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/builtin_llm.dart';
import '../../services/catalog.dart';
import '../../services/openai_compat.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'engine_pages.dart' show fitTone, confirm;

// ====================== Built into LocalAILine ======================

/// LocalAILine's own engine: install it once, pick a model (downloaded here), done.
/// Nothing else to run: no Ollama, no other app.
class BuiltinPanel extends StatefulWidget {
  const BuiltinPanel({super.key});
  @override
  State<BuiltinPanel> createState() => _BuiltinPanelState();
}

class _BuiltinPanelState extends State<BuiltinPanel> {
  String? bin;
  bool checked = false, installing = false;
  final link = TextEditingController();
  Map<String, String> ollamaFiles = {};
  String? ollamaPick;

  @override
  void initState() {
    super.initState();
    _check();
    ollamaFiles = BuiltinEngine.ollamaModels();
  }

  Future<void> _check() async {
    final b = await context.read<AppState>().builtin.binary();
    if (!mounted) return;
    setState(() {
      bin = b;
      checked = true;
    });
  }

  Future<void> _install() async {
    final s = context.read<AppState>();
    setState(() => installing = true);
    try {
      await s.builtin.install();
      await _check();
      await s.startBuiltin();
      s.toast('The built-in engine is installed.');
    } catch (e) {
      s.toast('$e');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final e = s.builtin;
    final hw = s.hardware;
    final rec = BuiltinEngine.recommend(hw);
    final path = s.builtinModelPath;

    final (lamp, title, sub) = !checked
        ? (LampState.off, 'Checking…', '')
        : bin == null
            ? (LampState.off, 'Needs llama.cpp (free, open source)', 'One click installs it with Homebrew. It runs the model inside LocalAILine.')
            : path == null
                ? (LampState.off, 'Choose a model below', 'It downloads once and stays on this computer.')
                : switch (e.state) {
                    EngineRun.running => (
                        LampState.on,
                        'Running · ${s.llmLabel}',
                        'Ready for ${e.runningLines} call${e.runningLines == 1 ? '' : 's'} at once · ${e.ctxPerSlot ~/ 1024}k each · nothing leaves this computer'
                      ),
                    EngineRun.starting => (LampState.off, 'Starting ${s.llmLabel}…', 'Loading the model into memory.'),
                    EngineRun.failed => (LampState.off, 'Stopped', e.problem ?? 'It stopped. Press Start to try again.'),
                    _ => (LampState.off, 'Not running', 'Press Start.'),
                  };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Row(children: [
          Lamp(lamp),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty) Muted(sub),
            ]),
          ),
          if (checked && bin == null)
            Btn(installing ? 'Installing…' : 'Install', icon: Icons.download, kind: BtnKind.primary, small: true, onPressed: installing ? null : _install),
          if (bin != null && path != null && e.state != EngineRun.running)
            Btn(e.state == EngineRun.starting ? 'Starting…' : 'Start', small: true, kind: BtnKind.primary,
                onPressed: e.state == EngineRun.starting ? null : s.startBuiltin),
          if (e.state == EngineRun.running) Btn('Stop', small: true, onPressed: e.stop),
        ]),
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Choose the model',
        trailing: hw == null ? null : Muted('Up to ${hw.modelBudgetGb.toStringAsFixed(0)} GB fits here', mono: true),
        children: [
          for (final m in BuiltinEngine.catalog) _modelTile(s, m, rec),
          for (final f in e.localFiles().where((f) => !BuiltinEngine.catalog.any((m) => m.file == p.basename(f.path)))) _fileTile(s, f),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Field(
                label: 'Another model from Hugging Face',
                hint: 'Paste the link to a .gguf file (Q4_K_M is a good size).',
                child: Row(children: [
                  Expanded(child: TextField(controller: link, decoration: const InputDecoration(hintText: 'https://huggingface.co/…/resolve/main/model-Q4_K_M.gguf'))),
                  const SizedBox(width: 8),
                  Btn('Download', icon: Icons.download, small: true, onPressed: () => s.downloadBuiltinLink(link.text)),
                ]),
              ),
              if (s.pulls.keys.any((k) => k.startsWith('builtin:') && !BuiltinEngine.catalog.any((m) => k == 'builtin:${m.id}'))) ...[
                const SizedBox(height: 8),
                Meter(s.pulls.entries.firstWhere((x) => x.key.startsWith('builtin:') && !BuiltinEngine.catalog.any((m) => x.key == 'builtin:${m.id}')).value ?? 0, color: LL.amber),
              ],
              if (ollamaFiles.isNotEmpty) ...[
                const SizedBox(height: 14),
                Field(
                  label: 'Or use a model already downloaded with Ollama',
                  hint: 'Uses Ollama’s copy of the file: no second download, and Ollama doesn’t need to run.',
                  child: Row(children: [
                    Expanded(
                      child: Dropdown<String>(
                        value: ollamaPick ?? ollamaFiles.keys.first,
                        items: {for (final k in ollamaFiles.keys) k: k},
                        onChanged: (v) => setState(() => ollamaPick = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Btn('Use', small: true, onPressed: () => s.setBuiltinModel(ollamaFiles[ollamaPick ?? ollamaFiles.keys.first]!)),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
      if (e.log.isNotEmpty && e.state == EngineRun.failed) ...[
        const SizedBox(height: 8),
        Mono(e.log.reversed.take(4).toList().reversed.join('\n'), size: 11.5),
      ],
    ]);
  }

  Widget _modelTile(AppState s, BuiltinModel m, BuiltinModel rec) {
    final hw = s.hardware;
    final have = s.builtin.downloaded(m);
    final selected = have && (s.builtinModel == m.id || s.builtinModel == m.file);
    final key = 'builtin:${m.id}';
    final pulling = s.pulls.containsKey(key);
    final fit = hw == null ? null : m.fitFor(hw);
    return Tile(
      onTap: have && !selected ? () => s.setBuiltinModel(m.id) : null,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? LL.green : context.c.muted, size: 20),
      title: Row(children: [
        Flexible(child: Text(m.name)),
        const SizedBox(width: 8),
        Muted('${m.sizeGb.toStringAsFixed(1)} GB', mono: true),
        if (m == rec) ...[const SizedBox(width: 8), const Pill('Best for this computer', tone: Tone.amber)],
      ]),
      subtitle: pulling
          ? Padding(padding: const EdgeInsets.only(top: 6, right: 30), child: Meter(s.pulls[key] ?? 0, color: LL.amber))
          : Muted(have ? (selected ? 'Downloaded · in use' : 'Downloaded · tap to use') : m.note),
      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (fit != null) Pill(fit.label, tone: fitTone(fit)),
        if (!have)
          Btn(pulling ? '${((s.pulls[key] ?? 0) * 100).toStringAsFixed(0)}%' : 'Download', icon: Icons.download, small: true,
              kind: m == rec ? BtnKind.primary : BtnKind.normal, onPressed: pulling || fit == Fit.tooLarge ? null : () => s.downloadBuiltin(m)),
        if (have && !selected) Btn('Use', small: true, onPressed: () => s.setBuiltinModel(m.id)),
        if (have && !selected)
          Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
            if (await confirm(context, 'Delete ${m.name}?', 'This frees ${m.sizeGb.toStringAsFixed(1)} GB. You can download it again later.', 'Delete')) {
              await s.builtin.deleteModel(p.join(s.builtin.modelsDir, m.file));
            }
          }),
      ]),
    );
  }

  Widget _fileTile(AppState s, File f) {
    final name = p.basename(f.path);
    final selected = s.builtinModel == name || s.builtinModel == f.path;
    return Tile(
      onTap: selected ? null : () => s.setBuiltinModel(name),
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? LL.green : context.c.muted, size: 20),
      title: Row(children: [
        Flexible(child: Text(p.basenameWithoutExtension(name))),
        const SizedBox(width: 8),
        Muted('${(f.lengthSync() / 1e9).toStringAsFixed(1)} GB', mono: true),
      ]),
      subtitle: Muted(selected ? 'Added from a link · in use' : 'Added from a link · tap to use'),
      trailing: selected
          ? null
          : Btn('', icon: Icons.delete_outline, small: true, kind: BtnKind.ghost, onPressed: () async {
              if (await confirm(context, 'Delete $name?', 'You can download it again later.', 'Delete')) await s.builtin.deleteModel(f.path);
            }),
    );
  }
}

// ====================== Your own AI server ======================

/// vLLM, LM Studio, llama.cpp, MLX, LocalAI, Jan or any server that speaks OpenAI's format:
/// address, optional key, Test, pick the model, Use.
class AiServerPanel extends StatefulWidget {
  const AiServerPanel({super.key, this.onCancel, this.onSaved});
  final VoidCallback? onCancel, onSaved;
  @override
  State<AiServerPanel> createState() => _AiServerPanelState();
}

class _AiServerPanelState extends State<AiServerPanel> {
  ServerKind kind = ServerKind.vllm;
  final url = TextEditingController(), key = TextEditingController(), modelText = TextEditingController();
  List<String> models = [];
  String? model, result;
  bool testing = false, ok = false, editing = true, noThinking = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppState>().aiServer;
    if (c != null) {
      kind = c.kind;
      url.text = c.baseUrl;
      key.text = c.apiKey;
      model = c.model;
      modelText.text = c.model;
      noThinking = c.disableThinking;
      editing = false;
    } else {
      url.text = kind.defaultUrl;
    }
  }

  OpenAiServer get _config => OpenAiServer(
      baseUrl: url.text.trim(), apiKey: key.text.trim(), model: models.isEmpty ? modelText.text.trim() : (model ?? ''), kind: kind, disableThinking: noThinking);

  Future<void> _test() async {
    final s = context.read<AppState>();
    setState(() {
      testing = true;
      result = null;
      ok = false;
    });
    try {
      final list = await s.compat.models(_config);
      setState(() {
        models = list;
        model = list.contains(model) ? model : list.firstOrNull;
      });
      if (_config.model.isEmpty) throw Exception('Connected, but the server lists no models. Type the model’s name.');
      final reply = await s.compat.test(_config);
      setState(() {
        ok = true;
        result = 'Connected · the model answered “${reply.trim().length > 40 ? '${reply.trim().substring(0, 40)}…' : reply.trim()}”. Press Use.';
      });
    } catch (e) {
      setState(() => result = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> _use() async {
    final s = context.read<AppState>();
    await s.saveAiServer(_config);
    s.toast('Ava now thinks with ${kind.label} (${_config.model}).');
    setState(() => editing = false);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.aiServer;
    if (!editing && c != null) {
      return Panel(
        child: Row(children: [
          const Lamp(LampState.on),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.kind.label} · ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Muted('At ${c.base}. Calls and chats are answered by this server.'),
            ]),
          ),
          Btn('Change', small: true, onPressed: () => setState(() => editing = true)),
          const SizedBox(width: 6),
          Btn('Disconnect', small: true, kind: BtnKind.ghost, onPressed: () async {
            await s.removeAiServer();
            widget.onCancel?.call();
          }),
        ]),
      );
    }
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Connect your own AI server', style: displayStyle(context, 17)),
        const SizedBox(height: 4),
        const Muted('Any program that speaks OpenAI’s format, on this computer or your network. Hearing and voice still run here.'),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in ServerKind.values)
            ChoiceChip(
              label: Text(k.label),
              selected: kind == k,
              onSelected: (_) => setState(() {
                // Fill in its usual address, unless one was typed already.
                if (url.text.trim().isEmpty || ServerKind.values.any((o) => o.defaultUrl == url.text.trim())) url.text = k.defaultUrl;
                kind = k;
                models = [];
                ok = false;
                result = null;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Grid(cols: 2, children: [
          Field(label: 'Address', hint: 'Ends in /v1 (added if missing).', child: TextField(controller: url, decoration: const InputDecoration(hintText: 'http://127.0.0.1:8000/v1'))),
          Field(label: 'API key (if it needs one)', child: TextField(controller: key, obscureText: true)),
        ]),
        const SizedBox(height: 12),
        if (models.length > 1)
          Field(label: 'Model', child: Dropdown(value: model ?? models.first, items: {for (final m in models) m: m}, onChanged: (v) => setState(() => model = v)))
        else if (models.isEmpty)
          Field(label: 'Model', hint: 'Press Test to list the server’s models, or type its name.', child: TextField(controller: modelText))
        else
          Muted('Model: ${models.first}'),
        const SizedBox(height: 6),
        SwitchRow('Answer without thinking out loud first (faster, for Qwen3 and similar)', value: noThinking, onChanged: (v) => setState(() => noThinking = v)),
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
          if (widget.onCancel != null)
            Btn('Cancel', kind: BtnKind.ghost, onPressed: () {
              if (s.aiServer != null) {
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
