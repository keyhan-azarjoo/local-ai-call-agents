import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

enum EnginePart { redis, livekit, sip, bridge, whisper, accurate, agent }

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
  /// Ready to talk (phone calling and the larger hearing model are optional).
  bool get ready => [EnginePart.livekit, EnginePart.whisper, EnginePart.agent].every((e) => state[e] == PartState.running);

  /// Phone calls (LiveKit SIP) are running.
  bool get phoneReady => ready && state[EnginePart.sip] == PartState.running;

  static const redisPort = 6390;

  /// Calls are set up over TLS (needs the local certificate).
  bool sipTls = false;

  /// LiveKit's phone (SIP) service: built from source once (needs Go), kept with the app's data.
  Future<String?> sipBinary() async {
    for (final f in [p.join(dataDir, 'bin', 'livekit-sip'), p.join(Platform.environment['HOME'] ?? '', 'go', 'bin', 'livekit-sip')]) {
      if (File(f).existsSync()) return f;
    }
    return which('livekit-sip');
  }

  /// The call bridge: keeps this computer signed in to your private Twilio SIP address over a
  /// connection it opens itself, so incoming calls arrive without any router settings.
  String get bridgeBinary => p.join(dataDir, 'bin', 'll-sipreg');

  Future<void> startBridge(Map<String, String> env) async {
    if (state[EnginePart.bridge] == PartState.running || !File(bridgeBinary).existsSync()) return;
    await _spawn(EnginePart.bridge, bridgeBinary, [], env: {...env, 'LL_LOCAL_SIP': '127.0.0.1:5080'},
        healthy: () async => log.any((l) => l.contains('[bridge]') && l.contains('registered')));
  }

  Future<void> stopBridge() async {
    _procs.remove(EnginePart.bridge)?.kill();
    state[EnginePart.bridge] = PartState.stopped;
    notifyListeners();
  }

  /// Builds the call bridge from its source (in the app).
  Future<void> installBridge({required Map<String, String> files}) async {
    final go = await which('go');
    if (go == null) throw Exception('Answering calls needs Go: brew install go');
    final src = Directory(p.join(Directory.systemTemp.path, 'localailine-bridge-${DateTime.now().millisecondsSinceEpoch}'))..createSync();
    files.forEach((name, text) => File(p.join(src.path, name)).writeAsStringSync(text));
    Directory(p.join(dataDir, 'bin')).createSync(recursive: true);
    final r = await Process.run(go, ['build', '-o', bridgeBinary, '.'], workingDirectory: src.path,
        environment: {'PATH': '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH']}'});
    await src.delete(recursive: true);
    if (r.exitCode != 0) throw Exception('Couldn’t build the call bridge: ${r.stderr}');
    _log('Call bridge installed.');
  }

  /// Builds the phone service from LiveKit SIP's source, with our patch (each call's audio
  /// port learns its outside port by STUN, so calls work behind home routers).
  static const sipVersion = 'v1.17.0';

  Future<void> installPhone({required String patch}) async {
    final brew = await which('brew');
    final go = await which('go');
    if (brew == null || go == null) throw Exception('Phone calling needs Homebrew and Go: brew install go');
    final env = {
      'PKG_CONFIG_PATH': '/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig',
      'PATH': '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH']}',
    };
    Future<String> run(String exe, List<String> args, {String? dir}) async {
      _log('\$ ${p.basename(exe)} ${args.join(' ')}');
      final pr = await Process.start(exe, args, environment: env, workingDirectory: dir);
      final out = StringBuffer();
      pr.stdout.transform(utf8.decoder).listen((l) {
        out.write(l);
        _log(l.trim());
      });
      pr.stderr.transform(utf8.decoder).listen((l) => _log(l.trim()));
      if (await pr.exitCode != 0) throw Exception('Install step failed: ${p.basename(exe)} ${args.take(2).join(' ')}');
      return out.toString();
    }

    await run(brew, ['install', 'opus', 'libsoxr', 'pkg-config', 'redis']);
    final info = jsonDecode(await run(go, ['mod', 'download', '-json', 'github.com/livekit/sip@$sipVersion'])) as Map;
    final src = Directory(p.join(Directory.systemTemp.path, 'localailine-sip-${DateTime.now().millisecondsSinceEpoch}'));
    await run('/bin/cp', ['-R', '${info['Dir']}', src.path]);
    await run('/bin/chmod', ['-R', 'u+w', src.path]);
    final patchFile = File(p.join(src.path, 'localailine.patch'))..writeAsStringSync(patch);
    await run('/usr/bin/patch', ['-p1', '-i', patchFile.path], dir: src.path);
    final bin = Directory(p.join(dataDir, 'bin'))..createSync(recursive: true);
    await run(go, ['build', '-o', p.join(bin.path, 'livekit-sip'), './cmd/livekit-sip'], dir: src.path);
    await src.delete(recursive: true);
    _log('Phone calling installed.');
  }

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
    // One log for all parts, always appended (it's cleared when the engine starts).
    final file = File(p.join(dataDir, 'voice-engine.log')).openWrite(mode: FileMode.append);
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
    // Any engine part of ours still running (e.g. the app was force-quit): it would keep old
    // code, hold ports and memory, and the new one couldn't start.
    if (!Platform.isWindows) {
      for (final pattern in [
        script,
        'whisper-server .*--port $whisperPort',
        'whisper-server .*--port $accuratePort',
        'livekit-server --config ${p.join(dataDir, 'livekit.yaml')}',
        'redis-server .*:$redisPort',
        p.join(dataDir, 'bin', 'livekit-sip'),
        bridgeBinary,
      ]) {
        Process.runSync('pkill', ['-f', pattern]);
      }
    }
  }

  /// One start at a time (live voice and incoming calls may both ask for it).
  Future<void>? _starting;
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    problem = null;
    _killStale();
    if (_procs.isEmpty) {
      final f = File(p.join(dataDir, 'voice-engine.log'));
      if (f.existsSync() && f.lengthSync() > 0) f.renameSync('${f.path}.old');
    }
    final miss = await missing();
    if (miss.isNotEmpty) {
      problem = 'Missing: ${miss.join(', ')}';
      for (final e in EnginePart.values) {
        state[e] = PartState.missing;
      }
      notifyListeners();
      return;
    }
    // Phone calls need LiveKit's SIP service, which talks to LiveKit through Redis.
    final sipBin = await sipBinary();
    final redis = sipBin == null ? null : await which('redis-server');
    if (redis != null && state[EnginePart.redis] != PartState.running) {
      await _spawn(EnginePart.redis, redis, ['--port', '$redisPort', '--bind', '127.0.0.1', '--save', '', '--appendonly', 'no'],
          healthy: () async {
            try {
              final s = await Socket.connect('127.0.0.1', redisPort, timeout: const Duration(milliseconds: 300));
              s.destroy();
              return true;
            } catch (_) {
              return false;
            }
          });
    }
    final withRedis = state[EnginePart.redis] == PartState.running;
    if (state[EnginePart.livekit] != PartState.running) {
      final cfg = File(p.join(dataDir, 'livekit.yaml'))
        ..writeAsStringSync('port: $livekitPort\nbind_addresses: ["127.0.0.1"]\nrtc:\n  tcp_port: 7881\n  node_ip: 127.0.0.1\n'
            '${withRedis ? 'redis:\n  address: 127.0.0.1:$redisPort\n' : ''}keys:\n  $apiKey: $apiSecret\n');
      await _spawn(EnginePart.livekit, (await which('livekit-server'))!, ['--config', cfg.path], healthy: () => _ok('http://127.0.0.1:$livekitPort'));
    }
    if (withRedis && sipBin != null && state[EnginePart.sip] != PartState.running) {
      // Calls are set up over TLS: home routers' "SIP ALG" rewrites plain call setup and the
      // other side's audio never arrives. A local self-signed certificate is enough for that.
      final crt = p.join(dataDir, 'sip.crt'), key = p.join(dataDir, 'sip.key');
      if (!File(crt).existsSync() || !File(key).existsSync()) {
        await Process.run('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', crt, '-days', '3650', '-subj', '/CN=localailine']);
      }
      final tls = File(crt).existsSync() ? 'tls:\n  port: 5061\n  port_listen: 5061\n  certs:\n    - cert_file: "$crt"\n      key_file: "$key"\n' : '';
      final cfg = File(p.join(dataDir, 'sip.yaml'))
        ..writeAsStringSync('api_key: $apiKey\napi_secret: $apiSecret\nws_url: $livekitUrl\nredis:\n  address: 127.0.0.1:$redisPort\n'
            'sip_port: 5080\nrtp_port: 52000-52500\nuse_external_ip: true\n${tls}logging:\n  level: info\n');
      sipTls = tls.isNotEmpty;
      // Each call's audio port asks STUN for its outside port (home routers renumber ports).
      await _spawn(EnginePart.sip, sipBin, ['--config', cfg.path], env: {'LIVEKIT_SIP_MEDIA_STUN': 'global.stun.twilio.com:3478'}, healthy: () async => log.any((l) => l.contains('[sip]') && l.contains('sip signaling listening')));
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
    for (final e in [EnginePart.agent, EnginePart.accurate, EnginePart.whisper, EnginePart.bridge, EnginePart.sip, EnginePart.livekit, EnginePart.redis]) {
      _procs.remove(e)?.kill();
      state[e] = PartState.stopped;
    }
    if (_pidFile.existsSync()) _pidFile.deleteSync();
    notifyListeners();
  }

  /// A signed LiveKit access token (JWT, HS256) for joining one room.
  Future<String> token({required String identity, String room = '', String? name, Duration ttl = const Duration(hours: 2), bool sipAdmin = false}) async {
    String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final head = b64({'alg': 'HS256', 'typ': 'JWT'});
    final body = b64({
      'iss': apiKey,
      'sub': identity,
      'name': name ?? identity,
      'nbf': now - 10,
      'exp': now + ttl.inSeconds,
      'video': {'room': room, 'roomJoin': room.isNotEmpty, 'roomCreate': sipAdmin, 'canPublish': true, 'canSubscribe': true, 'canPublishData': true},
      if (sipAdmin) 'sip': {'admin': true, 'call': true},
    });
    final mac = await Hmac.sha256().calculateMac(utf8.encode('$head.$body'), secretKey: SecretKey(utf8.encode(apiSecret)));
    return '$head.$body.${base64Url.encode(mac.bytes).replaceAll('=', '')}';
  }
}
