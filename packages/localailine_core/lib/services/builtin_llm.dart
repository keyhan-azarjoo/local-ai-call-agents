import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localailine_core/notifier.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'catalog.dart' show Fit;
import 'hardware.dart';
import 'voice_engine.dart' show VoiceEngine;
import 'package:localailine_model/llm.dart';
export 'package:localailine_model/llm.dart' show BuiltinModel, EngineRun;

/// LocalAILine's own AI engine: runs llama.cpp's `llama-server` on this computer, with a model
/// file it downloads itself. No Ollama, no other app. It speaks OpenAI's format on
/// http://127.0.0.1:8940/v1, so the app talks to it like any OpenAI-compatible server.
class BuiltinEngine extends Notifier {
  BuiltinEngine({required this.dataDir, http.Client? client}) : _c = client ?? http.Client();
  final String dataDir;
  final http.Client _c;

  static const port = 8940;
  static String get baseUrl => 'http://127.0.0.1:$port/v1';

  /// Models we suggest (sizes from Hugging Face, Q4_K_M: a good balance of size and quality).
  static const catalog = [
    BuiltinModel('qwen3-4b-instruct-2507', 'Qwen3 4B Instruct (2507)', 'unsloth/Qwen3-4B-Instruct-2507-GGUF', 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
        2497281120, 4, 'Quick and good with tools. Our pick for most computers.'),
    BuiltinModel('qwen3-8b', 'Qwen3 8B', 'unsloth/Qwen3-8B-GGUF', 'Qwen3-8B-Q4_K_M.gguf', 5027784512, 8,
        'Smarter, a little slower. Needs 16 GB or more.', thinks: true),
    BuiltinModel('qwen2.5-7b-instruct', 'Qwen2.5 7B Instruct', 'bartowski/Qwen2.5-7B-Instruct-GGUF', 'Qwen2.5-7B-Instruct-Q4_K_M.gguf', 4683074240, 7,
        'Steady all-rounder, good with tools.'),
    BuiltinModel('llama-3.2-3b-instruct', 'Llama 3.2 3B Instruct', 'bartowski/Llama-3.2-3B-Instruct-GGUF', 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        2019377696, 3, 'Small and fast (Meta).'),
    BuiltinModel('phi-4-mini-instruct', 'Phi-4 mini Instruct', 'unsloth/Phi-4-mini-instruct-GGUF', 'Phi-4-mini-instruct-Q4_K_M.gguf', 2491874272, 3.8,
        'Small and careful (Microsoft).'),
    BuiltinModel('gemma-3-4b-it', 'Gemma 3 4B', 'ggml-org/gemma-3-4b-it-GGUF', 'gemma-3-4b-it-Q4_K_M.gguf', 2489757856, 4,
        'Friendly writing, many languages (Google). Weaker with tools.'),
    BuiltinModel('granite-4.0-micro', 'Granite 4.0 Micro', 'ibm-granite/granite-4.0-micro-GGUF', 'granite-4.0-micro-Q4_K_M.gguf', 2099502528, 3,
        'Small business model with tool use (IBM).'),
    BuiltinModel('qwen3-1.7b', 'Qwen3 1.7B', 'unsloth/Qwen3-1.7B-GGUF', 'Qwen3-1.7B-Q4_K_M.gguf', 1107409472, 1.7,
        'Very light, for older computers.', thinks: true),
    BuiltinModel('qwen2.5-0.5b-instruct', 'Qwen2.5 0.5B Instruct', 'bartowski/Qwen2.5-0.5B-Instruct-GGUF', 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
        397808192, .5, 'Tiny · for testing only.'),
  ];

  static BuiltinModel? byId(String? id) => catalog.where((m) => m.id == id || m.file == id).firstOrNull;

  /// The best suggested model for this computer: the strongest that fits with room to spare.
  static BuiltinModel recommend(Hardware? hw) {
    if (hw == null) return catalog.first;
    for (final id in ['qwen3-4b-instruct-2507', 'llama-3.2-3b-instruct', 'qwen3-1.7b', 'qwen2.5-0.5b-instruct']) {
      final m = byId(id)!;
      if (m.fitFor(hw) == Fit.great || m.fitFor(hw) == Fit.fits) return m;
    }
    return byId('qwen2.5-0.5b-instruct')!;
  }

  String get modelsDir => p.join(dataDir, 'models', 'llm');
  File get _pidFile => File(p.join(dataDir, 'builtin-llm.pid'));
  File get logFile => File(p.join(dataDir, 'builtin-llm.log'));

  EngineRun state = EngineRun.stopped;
  String? problem;

  /// The model file running now (full path) and its name for requests.
  String? runningPath;
  int runningLines = 0;
  int ctxPerSlot = 16384;
  Process? _proc;
  bool _stopping = false;
  final _crashes = <DateTime>[];

  /// Downloads in progress: model id → fraction done (null = starting).
  final downloads = <String, double?>{};

  // ---------------- the program ----------------

  /// Where llama-server is: a copy kept with the app's data first, else Homebrew's, else on the PATH.
  Future<String?> binary() async {
    final own = File(p.join(dataDir, 'bin', 'llama-server'));
    if (own.existsSync()) return own.path;
    try {
      final r = await Process.run('brew', ['--prefix', 'llama.cpp'], environment: _brewEnv);
      final f = File(p.join('${r.stdout}'.trim(), 'bin', 'llama-server'));
      if (r.exitCode == 0 && f.existsSync()) return f.path;
    } catch (_) {}
    return VoiceEngine.which('llama-server');
  }

  static Map<String, String> get _brewEnv => {'PATH': '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH']}'};

  /// Installs llama.cpp with Homebrew (a few seconds: it comes ready-built).
  Future<void> install() async {
    final brew = await VoiceEngine.which('brew');
    if (brew == null) throw Exception('Install Homebrew first (brew.sh), then press Install again.');
    _log('\$ brew install llama.cpp');
    final pr = await Process.start(brew, ['install', 'llama.cpp'], environment: _brewEnv);
    pr.stdout.transform(utf8.decoder).listen((l) => _log(l.trim()));
    pr.stderr.transform(utf8.decoder).listen((l) => _log(l.trim()));
    if (await pr.exitCode != 0) throw Exception('brew install llama.cpp did not finish. See the engine log.');
    if (state == EngineRun.missing) state = EngineRun.stopped;
    notifyListeners();
  }

  // ---------------- model files ----------------

  /// The full path for a model choice: a suggested model's id, a file in the models folder, or a full path.
  String? pathFor(String? choice) {
    if (choice == null || choice.isEmpty) return null;
    final m = byId(choice);
    final f = File(m != null ? p.join(modelsDir, m.file) : (p.isAbsolute(choice) ? choice : p.join(modelsDir, choice)));
    return f.existsSync() ? f.path : null;
  }

  bool downloaded(BuiltinModel m) => File(p.join(modelsDir, m.file)).existsSync();

  /// Every .gguf in the models folder (suggested or added from a link).
  List<File> localFiles() {
    final d = Directory(modelsDir);
    if (!d.existsSync()) return [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf') && !p.basename(f.path).startsWith('mmproj')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// A Hugging Face link to a .gguf file, in any of its usual shapes, as a download address.
  /// e.g. https://huggingface.co/org/repo/blob/main/x.gguf or hf.co/org/repo/resolve/main/x.gguf?download=true
  static Uri? hfUrl(String link) {
    var s = link.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || !u.path.toLowerCase().endsWith('.gguf')) return null;
    if (!{'huggingface.co', 'hf.co', 'www.huggingface.co'}.contains(u.host)) return null;
    return Uri.https('huggingface.co', u.path.replaceFirst('/blob/', '/resolve/'));
  }

  /// Downloads a model file into the models folder, reporting progress (0–1). Resumes a
  /// broken download; the file only gets its real name once complete.
  Stream<double> download(Uri url, String fileName) async* {
    Directory(modelsDir).createSync(recursive: true);
    final dest = File(p.join(modelsDir, fileName));
    if (dest.existsSync()) {
      yield 1;
      return;
    }
    final part = File('${dest.path}.part');
    final have = part.existsSync() ? part.lengthSync() : 0;
    final req = http.Request('GET', url);
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    final res = await _c.send(req);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Hugging Face needs you to accept this model’s licence on its page first (or it is private).');
    }
    if (res.statusCode != 200 && res.statusCode != 206) throw Exception('Download failed (${res.statusCode}).');
    final resumed = res.statusCode == 206;
    final total = (res.contentLength ?? 0) + (resumed ? have : 0);
    var done = resumed ? have : 0;
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var last = DateTime.now();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0 && DateTime.now().difference(last).inMilliseconds > 250) {
          last = DateTime.now();
          yield done / total;
        }
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && part.lengthSync() < total) throw Exception('Download stopped early. Press Download again to carry on.');
    // GGUF files start with these four letters: anything else is an error page.
    final head = await part.openRead(0, 4).first;
    if (utf8.decode(head, allowMalformed: true) != 'GGUF') {
      part.deleteSync();
      throw Exception('That link did not give a model file.');
    }
    await part.rename(dest.path);
    yield 1;
  }

  Future<void> deleteModel(String path) async {
    final f = File(path);
    if (p.isWithin(modelsDir, path) && f.existsSync()) await f.delete();
    notifyListeners();
  }

  /// Models already downloaded with Ollama, as their model files (no second download needed).
  /// name → path of the file in Ollama's store.
  static Map<String, String> ollamaModels({String? home}) {
    final root = Directory(p.join(home ?? Platform.environment['OLLAMA_MODELS'] ?? p.join(Platform.environment['HOME'] ?? '', '.ollama', 'models')));
    final manifests = Directory(p.join(root.path, 'manifests', 'registry.ollama.ai'));
    if (!manifests.existsSync()) return {};
    final out = <String, String>{};
    for (final f in manifests.listSync(recursive: true).whereType<File>()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map;
        final layer = (j['layers'] as List).cast<Map>().where((l) => l['mediaType'] == 'application/vnd.ollama.image.model').firstOrNull;
        if (layer == null) continue;
        final blob = File(p.join(root.path, 'blobs', '${layer['digest']}'.replaceFirst(':', '-')));
        if (!blob.existsSync()) continue;
        final parts = p.split(p.relative(f.path, from: manifests.path)); // library/qwen3/4b
        final name = '${parts[parts.length - 2]}:${parts.last}';
        if (RegExp(r'embed|bge|minilm', caseSensitive: false).hasMatch(name)) continue;
        out[parts.first == 'library' ? name : '${parts.sublist(0, parts.length - 2).join('/')}/$name'] = blob.path;
      } catch (_) {}
    }
    return out;
  }

  // ---------------- running it ----------------

  /// Memory one call's conversation needs (8-bit store), in GB, for [ctx] words-pieces.
  static double kvGbPerSlot(double params, int ctx) => kvCacheGb(params, ctx);

  /// How much each call may hold: 16k when memory allows (as with Ollama), less on smaller computers.
  static int ctxPerSlotFor({required double budgetGb, required double modelGb, required double params, required int slots}) {
    final spare = budgetGb - modelGb - 1.0;
    for (final c in [16384, 12288, 8192]) {
      if (kvGbPerSlot(params, c) * slots <= spare) return c;
    }
    return 4096;
  }

  /// The command line for [lines] calls at the same time: one working place ("slot") per call plus a
  /// spare (test callers, warm-ups, the manager's chat), each holding [ctxPerSlot]; its memory
  /// stored at 8 bits (half the size); and its store of earlier prompts capped at 512 MB per line.
  static List<String> args({required String model, required int lines, required int ctxPerSlot, int port = port, String? alias}) {
    final slots = lines + 1;
    return [
      '-m', model,
      '--host', '127.0.0.1',
      '--port', '$port',
      '--jinja',
      '-c', '${ctxPerSlot * slots}',
      '-np', '$slots',
      '--cache-type-k', 'q8_0',
      '--cache-type-v', 'q8_0',
      '-fa', 'on',
      '--cache-ram', '${512 * lines}',
      '-ngl', '999',
      '--no-webui',
      if (alias != null) ...['--alias', alias],
    ];
  }

  /// The OpenAI-compatible address and model name to use while it runs.
  OpenAiServer server({bool disableThinking = false}) =>
      OpenAiServer(baseUrl: baseUrl, model: runningAlias, kind: ServerKind.llamaCpp, maxCtx: ctxPerSlot, disableThinking: disableThinking);

  String get runningAlias => runningPath == null ? 'localailine' : p.basenameWithoutExtension(runningPath!);

  Future<bool> healthy() async {
    try {
      final r = await _c.get(Uri.parse('http://127.0.0.1:$port/health')).timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Stops servers of ours left behind by an earlier run (e.g. after a crash).
  void killStale() => _killStale();

  void _killStale() {
    if (_proc != null) return;
    if (_pidFile.existsSync()) {
      for (final pid in _pidFile.readAsStringSync().split(' ').map(int.tryParse).nonNulls) {
        Process.killPid(pid);
      }
      _pidFile.deleteSync();
    }
    if (!Platform.isWindows) Process.runSync('pkill', ['-f', 'llama-server .*--port $port']);
  }

  Future<void>? _starting;

  /// Starts (or restarts, if the model or the number of calls changed) the engine with [modelPath].
  Future<void> start(String modelPath, {required int lines, Hardware? hw, double? params}) {
    if (_starting != null) return _starting!.then((_) => start(modelPath, lines: lines, hw: hw, params: params));
    return _starting = _start(modelPath, lines, hw, params).whenComplete(() => _starting = null);
  }

  Future<void> _start(String modelPath, int lines, Hardware? hw, double? params) async {
    final size = File(modelPath).existsSync() ? File(modelPath).lengthSync() / 1e9 : 4.0;
    final ctx = ctxPerSlotFor(budgetGb: hw?.modelBudgetGb ?? 8, modelGb: size, params: params ?? (size * 1.7), slots: lines + 1);
    if (_proc != null && state == EngineRun.running && runningPath == modelPath && runningLines == lines && ctxPerSlot == ctx && await healthy()) return;
    await stop();
    _killStale();
    problem = null;
    final bin = await binary();
    if (bin == null) {
      state = EngineRun.missing;
      problem = 'llama.cpp is not installed';
      notifyListeners();
      return;
    }
    runningPath = modelPath;
    runningLines = lines;
    ctxPerSlot = ctx;
    state = EngineRun.starting;
    notifyListeners();
    _stopping = false;
    final a = args(model: modelPath, lines: lines, ctxPerSlot: ctx, alias: runningAlias);
    _log('\$ llama-server ${a.join(' ')}');
    if (logFile.existsSync() && logFile.lengthSync() > 5e6) logFile.renameSync('${logFile.path}.old');
    final sink = logFile.openWrite(mode: FileMode.append);
    final pr = await Process.start(bin, a, workingDirectory: dataDir);
    _proc = pr;
    _pidFile.writeAsStringSync('${pr.pid}');
    pr.stdout.listen(sink.add);
    pr.stderr.listen(sink.add);
    unawaited(pr.exitCode.then((code) async {
      await sink.close();
      if (_proc != pr) return;
      _proc = null;
      if (_stopping) return;
      state = EngineRun.failed;
      problem = 'The engine stopped (exit $code). See builtin-llm.log.';
      _log(problem!);
      notifyListeners();
      // Crashed: start it again, unless it keeps crashing (then something is wrong with the model or memory).
      _crashes.add(DateTime.now());
      _crashes.removeWhere((t) => DateTime.now().difference(t).inMinutes > 10);
      if (_crashes.length <= 3) {
        await Future.delayed(const Duration(seconds: 2));
        if (_proc == null && !_stopping) await start(modelPath, lines: lines, hw: hw, params: params);
      }
    }));
    // Loading a model takes a few seconds (longer the first time, or for big ones).
    for (var i = 0; i < 360 && _proc == pr; i++) {
      if (await healthy()) {
        state = EngineRun.running;
        _log('Running ${p.basename(modelPath)} for $lines call${lines == 1 ? '' : 's'} at once (${ctx ~/ 1024}k each).');
        notifyListeners();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (_proc == pr) {
      state = EngineRun.failed;
      problem = 'The engine did not start in time.';
      notifyListeners();
    }
  }

  /// Stops it (on quitting the app, or before a restart).
  Future<void> stop() async {
    _stopping = true;
    final pr = _proc;
    _proc = null;
    if (pr != null) {
      pr.kill();
      try {
        await pr.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        pr.kill(ProcessSignal.sigkill);
      }
    }
    if (_pidFile.existsSync()) _pidFile.deleteSync();
    if (state != EngineRun.missing) state = EngineRun.stopped;
    notifyListeners();
  }

  /// Same as [stop], for when the app is closing and can't wait.
  void stopNow() {
    _stopping = true;
    _proc?.kill();
    _proc = null;
    try {
      if (_pidFile.existsSync()) _pidFile.deleteSync();
    } catch (_) {}
  }

  final log = <String>[];
  void _log(String line) {
    if (line.isEmpty) return;
    log.add('${DateTime.now().toIso8601String().substring(11, 19)} $line');
    if (log.length > 200) log.removeRange(0, log.length - 200);
    notifyListeners();
  }
}
