import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

enum EnginePart { livekit, whisper, accurate, agent }

enum PartState { missing, stopped, starting, running, failed }

/// Runs the live voice engine on this computer: the LiveKit server, whisper.cpp's
/// server (hearing, on the GPU) and the LiveKit Agents voice worker (Python).
/// Everything listens on localhost; calls get short-lived signed tokens.
class VoiceEngine extends ChangeNotifier {
  VoiceEngine({required this.dataDir, required this.appUrl, required this.appKey});
  final String dataDir;

  /// The LocalAILine app's engine endpoint (OpenAI-compatible) and its key.
  final String appUrl;
  final String appKey;

  static const livekitPort = 7880;
  static const whisperPort = 8910;
  static const accuratePort = 8912;
  static const apiKey = 'localailine';

  /// A private secret for this computer (LiveKit's dev keys are public).
  late final String apiSecret = _secret();
  final state = <EnginePart, PartState>{for (final e in EnginePart.values) e: PartState.stopped};
  final log = <String>[];
  final _procs = <EnginePart, Process>{};
  String? problem;

  String get livekitUrl => 'ws://127.0.0.1:$livekitPort';
  /// Ready to talk (the larger hearing model is optional).
  bool get ready => EnginePart.values.every((e) => e == EnginePart.accurate || state[e] == PartState.running);

  String _secret() {
    final f = File(p.join(dataDir, 'voice-engine.secret'));
    if (f.existsSync()) return f.readAsStringSync().trim();
    final s = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    f.writeAsStringSync(s);
    return s;
  }

  static Future<String?> which(String name, {List<String> extra = const []}) async {
    for (final dir in ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '${Platform.environment['HOME']}/.local/bin', ...extra]) {
      final f = File(p.join(dir, name));
      if (f.existsSync()) return f.path;
    }
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [name]);
      if (r.exitCode == 0) return (r.stdout as String).split('\n').first.trim();
    } catch (_) {}
    return null;
  }

  /// The Python environment with LiveKit Agents (created by the installer).
  String get engineDir => p.join(dataDir, 'engine');
  String get python => p.join(engineDir, '.venv', 'bin', 'python');
  String get script => p.join(engineDir, 'localline_voice.py');

  Future<String?> whisperModel() async {
    final home = Platform.environment['HOME'] ?? '';
    for (final f in [
      p.join(dataDir, 'models', 'stt', 'ggml-base.bin'),
      p.join(home, '.whisper-models', 'ggml-base.bin'),
      p.join(dataDir, 'models', 'stt', 'ggml-base.en.bin'),
      p.join(home, '.whisper-models', 'ggml-base.en.bin'),
    ]) {
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  /// The larger hearing model, for languages the fast one hears poorly (Persian, Arabic, …).
  static const accurateModel = 'ggml-large-v3-turbo-q5_0.bin';
  String? accurateModelPath() {
    for (final f in [p.join(dataDir, 'models', 'stt', accurateModel), p.join(Platform.environment['HOME'] ?? '', '.whisper-models', accurateModel)]) {
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  Future<void> _downloadAccurate() async {
    final f = File(p.join(dataDir, 'models', 'stt', accurateModel));
    f.parent.createSync(recursive: true);
    _log('Downloading the hearing model for more languages (550 MB)…');
    final res = await http.Client().send(http.Request('GET', Uri.parse('https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$accurateModel')));
    if (res.statusCode != 200) throw Exception('download failed (${res.statusCode})');
    final tmp = File('${f.path}.part');
    await res.stream.pipe(tmp.openWrite());
    await tmp.rename(f.path);
  }

  /// What is missing before the engine can run (empty = all there).
  Future<List<String>> missing() async => [
        if (await which('livekit-server') == null) 'LiveKit server (brew install livekit)',
        if (await which('whisper-server') == null) 'whisper.cpp (brew install whisper-cpp)',
        if (await whisperModel() == null) 'a hearing model (Voice & hearing → download Whisper base)',
        if (!File(python).existsSync() || !File(script).existsSync()) 'the voice engine (Install below)',
      ];

  void _log(String line) {
    log.add('${DateTime.now().toIso8601String().substring(11, 19)} $line');
    if (log.length > 300) log.removeRange(0, log.length - 300);
    notifyListeners();
  }

  /// Installs the voice engine: a private Python environment (uv) with LiveKit Agents
  /// and Piper, plus the engine script and its models.
  Future<void> install({required String engineScript}) async {
    final uv = await which('uv');
    if (uv == null) throw Exception('Install uv first: brew install uv');
    Directory(engineDir).createSync(recursive: true);
    await File(script).writeAsString(engineScript);
    Future<void> run(List<String> args) async {
      _log('\$ ${args.join(' ')}');
      final pr = await Process.start(args.first, args.sublist(1), workingDirectory: engineDir);
      pr.stdout.transform(utf8.decoder).listen((l) => _log(l.trim()));
      pr.stderr.transform(utf8.decoder).listen((l) => _log(l.trim()));
      if (await pr.exitCode != 0) throw Exception('Install step failed: ${args.take(3).join(' ')}');
    }

    if (!File(python).existsSync()) await run([uv, 'venv', '--python', '3.12', '.venv']);
    await run([uv, 'pip', 'install', '--python', python, 'livekit-agents[silero,turn-detector,openai]~=1.8', 'piper-tts', 'kokoro-onnx', 'numpy']);
    await run([python, script, 'download-files']);
    await _naturalVoice();
    _log('Voice engine installed.');
  }

  String get kokoroDir => p.join(dataDir, 'models', 'kokoro');
  bool get _hasKokoroPackage => Directory(p.join(engineDir, '.venv', 'lib')).existsSync() &&
      Directory(p.join(engineDir, '.venv', 'lib')).listSync().any((d) => Directory(p.join(d.path, 'site-packages', 'kokoro_onnx')).existsSync());

  /// The natural voice (Kokoro, ~340 MB): the package and its model files.
  Future<void> _naturalVoice() async {
    if (!_hasKokoroPackage) {
      final uv = await which('uv');
      if (uv != null) {
        _log('Adding the natural voice…');
        await Process.run(uv, ['pip', 'install', '--python', python, 'kokoro-onnx'], workingDirectory: engineDir);
      }
    }
    Directory(kokoroDir).createSync(recursive: true);
    const base = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0';
    for (final name in ['voices-v1.0.bin', 'kokoro-v1.0.onnx']) {
      final f = File(p.join(kokoroDir, name));
      if (f.existsSync() && f.lengthSync() > 1000000) continue;
      _log('Downloading $name…');
      final tmp = File('${f.path}.part');
      final res = await http.Client().send(http.Request('GET', Uri.parse('$base/$name')));
      if (res.statusCode != 200) throw Exception('Could not download $name (${res.statusCode})');
      await res.stream.pipe(tmp.openWrite());
      await tmp.rename(f.path);
    }
  }

  Future<bool> _ok(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 1));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> _spawn(EnginePart part, String exe, List<String> args, {Map<String, String> env = const {}, required Future<bool> Function() healthy}) async {
    state[part] = PartState.starting;
    notifyListeners();
    final pr = await Process.start(exe, args, environment: env, workingDirectory: dataDir);
    _procs[part] = pr;
    _savePids();
    final file = File(p.join(dataDir, 'voice-engine.log')).openWrite(mode: part == EnginePart.livekit ? FileMode.write : FileMode.append);
    void out(String s) {
      file.write(s.replaceAll(RegExp(r'^', multiLine: true), '[${part.name}] '));
      for (final l in const LineSplitter().convert(s)) {
        if (l.trim().isEmpty) continue;
        if (part == EnginePart.agent && l.contains('registered worker')) {
          state[part] = PartState.running;
          notifyListeners();
        }
        if (l.contains('TIMING') || l.contains('ERROR') || l.contains('Error') || l.contains('registered worker') || part != EnginePart.agent) {
          _log('[${part.name}] ${l.length > 300 ? l.substring(0, 300) : l}');
        }
      }
    }

    pr.stdout.transform(utf8.decoder).listen(out);
    pr.stderr.transform(utf8.decoder).listen(out);
    unawaited(pr.exitCode.then((code) {
      file.close();
      if (_procs[part] == pr) {
        _procs.remove(part);
        state[part] = code == 0 || code == -15 ? PartState.stopped : PartState.failed;
        _log('[${part.name}] stopped (exit $code)');
        notifyListeners();
      }
    }));
    for (var i = 0; i < 60 && state[part] == PartState.starting; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await healthy()) {
        state[part] = PartState.running;
        notifyListeners();
      }
    }
    if (state[part] != PartState.running) {
      state[part] = PartState.failed;
      notifyListeners();
    }
  }

  File get _pidFile => File(p.join(dataDir, 'voice-engine.pids'));
  void _savePids() => _pidFile.writeAsStringSync(_procs.values.map((e) => e.pid).join(' '));

  /// Stops engine processes left behind by an earlier run of the app (e.g. after a crash).
  void _killStale() {
    if (_procs.isNotEmpty) return;
    if (_pidFile.existsSync()) {
      for (final pid in _pidFile.readAsStringSync().split(' ').map(int.tryParse).nonNulls) {
        Process.killPid(pid);
      }
      _pidFile.deleteSync();
    }
    // Any voice agent of ours still running (e.g. the app was force-quit): it would keep
    // old code and hold the agent's port, so the new one couldn't start.
    if (!Platform.isWindows) Process.runSync('pkill', ['-f', script]);
  }

  Future<void> start() async {
    problem = null;
    _killStale();
    final miss = await missing();
    if (miss.isNotEmpty) {
      problem = 'Missing: ${miss.join(', ')}';
      for (final e in EnginePart.values) {
        state[e] = PartState.missing;
      }
      notifyListeners();
      return;
    }
    if (state[EnginePart.livekit] != PartState.running) {
      await _spawn(
        EnginePart.livekit,
        (await which('livekit-server'))!,
        ['--bind', '127.0.0.1', '--node-ip', '127.0.0.1', '--port', '$livekitPort', '--keys', '$apiKey: $apiSecret'],
        healthy: () => _ok('http://127.0.0.1:$livekitPort'),
      );
    }
    if (state[EnginePart.whisper] != PartState.running) {
      await _spawn(
        EnginePart.whisper,
        (await which('whisper-server'))!,
        ['-m', (await whisperModel())!, '--host', '127.0.0.1', '--port', '$whisperPort', '-l', 'auto', '-t', '${max(2, Platform.numberOfProcessors ~/ 2)}'],
        healthy: () => _ok('http://127.0.0.1:$whisperPort'),
      );
    }
    if (state[EnginePart.accurate] != PartState.running) {
      try {
        if (accurateModelPath() == null) await _downloadAccurate();
        // A 15-second window keeps it fast (~0.8 s); longer turns use the fast model.
        await _spawn(
          EnginePart.accurate,
          (await which('whisper-server'))!,
          ['-m', accurateModelPath()!, '--host', '127.0.0.1', '--port', '$accuratePort', '-ac', '768', '-nf', '-bo', '1', '-bs', '1', '-t', '${max(2, Platform.numberOfProcessors ~/ 2)}'],
          healthy: () => _ok('http://127.0.0.1:$accuratePort'),
        );
      } catch (e) {
        _log('Hearing for more languages unavailable: $e');
      }
    }
    if (state[EnginePart.agent] != PartState.running) {
      try {
        await _naturalVoice();
      } catch (e) {
        _log('Natural voice unavailable ($e); using the standard voice.');
      }
      await _spawn(
        EnginePart.agent,
        python,
        [script, 'start'],
        env: {
          'LIVEKIT_URL': livekitUrl,
          'LIVEKIT_API_KEY': apiKey,
          'LIVEKIT_API_SECRET': apiSecret,
          'LL_APP_URL': appUrl,
          'LL_LLM_BASE': '$appUrl/v1',
          'LL_LLM_KEY': appKey,
          'LL_WHISPER_URL': 'http://127.0.0.1:$whisperPort',
          if (state[EnginePart.accurate] == PartState.running) 'LL_WHISPER_ACCURATE_URL': 'http://127.0.0.1:$accuratePort',
          'LL_VOICES_DIR': p.join(dataDir, 'models', 'tts'),
          'LL_KOKORO_DIR': kokoroDir,
        },
        healthy: () async => state[EnginePart.agent] == PartState.running,
      );
    }
  }

  Future<void> stop() async {
    for (final e in [EnginePart.agent, EnginePart.accurate, EnginePart.whisper, EnginePart.livekit]) {
      _procs.remove(e)?.kill();
      state[e] = PartState.stopped;
    }
    if (_pidFile.existsSync()) _pidFile.deleteSync();
    notifyListeners();
  }

  /// A signed LiveKit access token (JWT, HS256) for joining one room.
  Future<String> token({required String identity, required String room, String? name, Duration ttl = const Duration(hours: 2)}) async {
    String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final head = b64({'alg': 'HS256', 'typ': 'JWT'});
    final body = b64({
      'iss': apiKey,
      'sub': identity,
      'name': name ?? identity,
      'nbf': now - 10,
      'exp': now + ttl.inSeconds,
      'video': {'room': room, 'roomJoin': true, 'canPublish': true, 'canSubscribe': true, 'canPublishData': true},
    });
    final mac = await Hmac.sha256().calculateMac(utf8.encode('$head.$body'), secretKey: SecretKey(utf8.encode(apiSecret)));
    return '$head.$body.${base64Url.encode(mac.bytes).replaceAll('=', '')}';
  }
}
