import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class OllamaModel {
  OllamaModel(this.name, this.sizeBytes, this.params, this.quant);
  final String name, params, quant;
  final int sizeBytes;
  double get sizeGb => sizeBytes / 1e9;

  /// Search-only models (used for documents) can't chat.
  bool get isEmbedding => RegExp(r'embed|bge|minilm|e5-|gte-', caseSensitive: false).hasMatch(name);
}

class LoadedModel {
  LoadedModel(this.name, this.sizeBytes, this.vramBytes);
  final String name;
  final int sizeBytes, vramBytes;
}

class PullProgress {
  PullProgress(this.status, this.completed, this.total);
  final String status;
  final int completed, total;
  double? get fraction => total > 0 ? completed / total : null;
}

class ChatMessage {
  ChatMessage(this.role, this.content, {this.images = const []});
  final String role; // system | user | assistant
  String content;

  /// Pictures for models that can see (base64 PNG or JPEG).
  final List<String> images;
  Map<String, String> toJson() => {'role': role, 'content': content};

  static String mimeOf(String b64) => b64.startsWith('/9j/') ? 'image/jpeg' : (b64.startsWith('UklG') ? 'image/webp' : 'image/png');
}

/// Talks to a local Ollama server (default http://127.0.0.1:11434).
class Ollama {
  Ollama({this.base = 'http://127.0.0.1:11434', http.Client? client}) : _c = client ?? http.Client();
  final String base;
  final http.Client _c;

  Uri _u(String path) => Uri.parse('$base$path');

  /// Where the Ollama program usually lives on each OS.
  static List<String> get _candidates => [
        if (Platform.isMacOS) ...[
          '/opt/homebrew/bin/ollama',
          '/usr/local/bin/ollama',
          '/Applications/Ollama.app/Contents/Resources/ollama',
        ],
        if (Platform.isLinux) ...['/usr/local/bin/ollama', '/usr/bin/ollama', '/snap/bin/ollama'],
        if (Platform.isWindows)
          '${Platform.environment['LOCALAPPDATA']}\\Programs\\Ollama\\ollama.exe',
      ];

  static String? findBinary() {
    for (final c in _candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<String?> version() async {
    try {
      final r = await _c.get(_u('/api/version')).timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map)['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Starts `ollama serve` in the background if it is installed but not running.
  Future<bool> start() async {
    if (await version() != null) return true;
    if (Platform.isMacOS && Directory('/Applications/Ollama.app').existsSync()) {
      await Process.run('open', ['-g', '-a', 'Ollama']);
    } else {
      final bin = findBinary();
      if (bin == null) return false;
      await Process.start(bin, ['serve'], mode: ProcessStartMode.detached);
    }
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await version() != null) return true;
    }
    return false;
  }

  static String get downloadUrl => 'https://ollama.com/download';

  Future<List<OllamaModel>> installed() async {
    final r = await _c.get(_u('/api/tags'));
    final list = (jsonDecode(r.body) as Map)['models'] as List? ?? [];
    return [
      for (final m in list)
        OllamaModel(
          m['name'] as String,
          (m['size'] as num?)?.toInt() ?? 0,
          (m['details']?['parameter_size'] as String?) ?? '',
          (m['details']?['quantization_level'] as String?) ?? '',
        )
    ];
  }

  Future<List<LoadedModel>> loaded() async {
    final r = await _c.get(_u('/api/ps'));
    final list = (jsonDecode(r.body) as Map)['models'] as List? ?? [];
    return [
      for (final m in list)
        LoadedModel(m['name'] as String, (m['size'] as num?)?.toInt() ?? 0, (m['size_vram'] as num?)?.toInt() ?? 0)
    ];
  }

  /// What a model can do, e.g. completion, tools, vision, thinking.
  Future<List<String>> capabilities(String model) async {
    try {
      final r = await _c.post(_u('/api/show'), body: jsonEncode({'model': model})).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return const [];
      return [for (final c in ((jsonDecode(r.body) as Map)['capabilities'] as List? ?? const [])) '$c'];
    } catch (_) {
      return const [];
    }
  }

  /// Loads a model into memory and keeps it there until [unload].
  Future<void> load(String model) async {
    final r = await _c.post(_u('/api/generate'), body: jsonEncode({'model': model, 'keep_alive': -1}));
    if (r.statusCode != 200) throw OllamaError(_err(r.body));
  }

  Future<void> unload(String model) async {
    await _c.post(_u('/api/generate'), body: jsonEncode({'model': model, 'keep_alive': 0}));
  }

  Future<void> delete(String model) async {
    final req = http.Request('DELETE', _u('/api/delete'))..body = jsonEncode({'model': model});
    final r = await _c.send(req);
    if (r.statusCode != 200) throw OllamaError('Could not delete $model (${r.statusCode}).');
  }

  Stream<PullProgress> pull(String model) async* {
    final req = http.Request('POST', _u('/api/pull'))..body = jsonEncode({'model': model, 'stream': true});
    final res = await _c.send(req);
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final m = jsonDecode(line) as Map;
      if (m['error'] != null) throw OllamaError(m['error'].toString());
      yield PullProgress(
          m['status']?.toString() ?? '', (m['completed'] as num?)?.toInt() ?? 0, (m['total'] as num?)?.toInt() ?? 0);
    }
  }

  /// Streams the assistant's reply token by token.
  /// With [json], the model can only answer with a JSON object.
  Stream<String> chat(String model, List<ChatMessage> messages, {bool disableThinking = false, int numCtx = 16384, bool json = false, double temperature = 0.6}) async* {
    final body = <String, Object?>{
      'model': model,
      'messages': [for (final m in messages) {...m.toJson(), if (m.images.isNotEmpty) 'images': m.images}],
      'stream': true,
      'keep_alive': -1,
      'options': {'num_ctx': numCtx, 'temperature': temperature},
      if (json) 'format': 'json',
    };
    // Only hybrid models honour think:false; thinking-only models would then
    // write their reasoning into the reply, so we leave them alone and
    // read just the answer (Ollama returns thinking in a separate field).
    if (disableThinking) body['think'] = false;
    final req = http.Request('POST', _u('/api/chat'))..body = jsonEncode(body);
    final res = await _c.send(req);
    if (res.statusCode != 200) {
      throw OllamaError(_err(await res.stream.bytesToString()));
    }
    var inThink = false;
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final m = jsonDecode(line) as Map;
      if (m['error'] != null) throw OllamaError(m['error'].toString());
      var piece = m['message']?['content'] as String? ?? '';
      // Some models inline <think>…</think> in the reply; drop it.
      if (piece.contains('<think>')) {
        inThink = true;
        piece = piece.split('<think>').first;
      }
      if (inThink) {
        if (!piece.contains('</think>')) continue;
        inThink = false;
        piece = piece.split('</think>').last;
      }
      if (piece.isNotEmpty) yield piece;
    }
  }

  static String _err(String body) {
    try {
      return (jsonDecode(body) as Map)['error']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}

class OllamaError implements Exception {
  OllamaError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Other engines we detect. Each speaks the OpenAI API.
class EngineStatus {
  EngineStatus(this.name, this.detail, this.state);
  final String name, detail;
  final EngineState state;
}

enum EngineState { running, installed, missing, unsupported }

Future<EngineStatus> detectLmStudio() async {
  try {
    final r = await http.get(Uri.parse('http://127.0.0.1:1234/v1/models')).timeout(const Duration(seconds: 1));
    if (r.statusCode == 200) return EngineStatus('LM Studio', 'Running · port 1234', EngineState.running);
  } catch (_) {}
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final paths = [
    if (Platform.isMacOS) '/Applications/LM Studio.app',
    '$home/.lmstudio',
    '$home/.cache/lm-studio',
  ];
  final found = paths.any((p) => Directory(p).existsSync());
  return EngineStatus(
      'LM Studio', found ? 'Installed · not running' : 'Not installed', found ? EngineState.installed : EngineState.missing);
}

Future<EngineStatus> detectLlamaCpp() async {
  final which = Platform.isWindows ? 'where' : 'which';
  try {
    final r = await Process.run(which, ['llama-server']);
    if (r.exitCode == 0) return EngineStatus('llama.cpp', 'Installed · llama-server', EngineState.installed);
  } catch (_) {}
  return EngineStatus('llama.cpp', 'Not installed', EngineState.missing);
}

EngineStatus detectVllm() => Platform.isLinux
    ? EngineStatus('vLLM', 'Needs an NVIDIA GPU', EngineState.missing)
    : EngineStatus('vLLM', 'Linux + NVIDIA GPU only', EngineState.unsupported);
