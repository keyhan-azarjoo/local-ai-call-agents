import 'catalog.dart' show Fit, fitOf;
import 'hardware.dart';

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

/// Other engines we detect. Each speaks the OpenAI API.
class EngineStatus {
  EngineStatus(this.name, this.detail, this.state);
  final String name, detail;
  final EngineState state;
}

enum EngineState { running, installed, missing, unsupported }

/// Cloud AI providers the user can connect instead of a local model.
enum CloudProvider {
  openai('OpenAI', 'API key from platform.openai.com'),
  azure('Azure OpenAI', 'Key and endpoint from your Azure OpenAI resource'),
  google('Google Gemini', 'API key from aistudio.google.com'),
  anthropic('Anthropic Claude', 'API key from console.anthropic.com');

  const CloudProvider(this.label, this.keyHint);
  final String label, keyHint;

  static CloudProvider? parse(String? s) => CloudProvider.values.where((p) => p.name == s).firstOrNull;
}

class CloudConfig {
  CloudConfig({required this.provider, required this.apiKey, this.endpoint = '', this.model = ''});
  final CloudProvider provider;
  final String apiKey;

  /// Azure only, e.g. `https://my-resource.openai.azure.com`.
  final String endpoint;

  /// Model id, or the deployment name for Azure.
  final String model;

  Map<String, String> toJson() => {'provider': provider.name, 'apiKey': apiKey, 'endpoint': endpoint, 'model': model};

  static CloudConfig? fromJson(Map<String, dynamic>? j) {
    final p = CloudProvider.parse(j?['provider'] as String?);
    if (p == null) return null;
    return CloudConfig(provider: p, apiKey: j!['apiKey'] ?? '', endpoint: j['endpoint'] ?? '', model: j['model'] ?? '');
  }

  CloudConfig withModel(String m) => CloudConfig(provider: provider, apiKey: apiKey, endpoint: endpoint, model: m);
}

/// Programs that run AI models and answer in OpenAI's format. The user picks one and we fill in
/// the address it usually has; any other OpenAI-compatible server works with "Other".
enum ServerKind {
  vllm('vLLM', 'http://127.0.0.1:8000/v1'),
  lmStudio('LM Studio', 'http://127.0.0.1:1234/v1'),
  llamaCpp('llama.cpp server', 'http://127.0.0.1:8080/v1'),
  mlx('MLX (mlx_lm.server)', 'http://127.0.0.1:8080/v1'),
  localAi('LocalAI', 'http://127.0.0.1:8080/v1'),
  jan('Jan', 'http://127.0.0.1:1337/v1'),
  ollama('Ollama (OpenAI mode)', 'http://127.0.0.1:11434/v1'),
  other('Other', '');

  const ServerKind(this.label, this.defaultUrl);
  final String label, defaultUrl;

  static ServerKind parse(String? s) => ServerKind.values.where((k) => k.name == s).firstOrNull ?? ServerKind.other;
}

/// An AI server the user runs themselves (vLLM, LM Studio, llama.cpp…), spoken to in OpenAI's format.
class OpenAiServer {
  OpenAiServer({required this.baseUrl, this.apiKey = '', this.model = '', this.kind = ServerKind.other, this.maxCtx = 16384, this.disableThinking = false});

  /// e.g. http://127.0.0.1:8000/v1 (a missing /v1 is added).
  final String baseUrl;
  final String apiKey, model;
  final ServerKind kind;

  /// How much the server holds per request (its own setting; we only size what we send by it).
  final int maxCtx;

  /// Ask models that can think out loud (e.g. Qwen3) not to: phone replies must start quickly.
  final bool disableThinking;

  /// The address, always ending in /v1 and without a trailing slash.
  String get base {
    var b = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) return b;
    if (!b.startsWith('http')) b = 'http://$b';
    b = b.replaceAll(RegExp(r'/chat/completions$'), '');
    return RegExp(r'/v\d+$').hasMatch(b) ? b : '$b/v1';
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      };

  Map<String, Object> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'kind': kind.name,
        'maxCtx': maxCtx,
        'disableThinking': disableThinking,
      };

  static OpenAiServer? fromJson(Map<String, dynamic>? j) {
    final url = j?['baseUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    return OpenAiServer(
      baseUrl: url,
      apiKey: j!['apiKey'] as String? ?? '',
      model: j['model'] as String? ?? '',
      kind: ServerKind.parse(j['kind'] as String?),
      maxCtx: (j['maxCtx'] as num?)?.toInt() ?? 16384,
      disableThinking: j['disableThinking'] == true,
    );
  }

  OpenAiServer copyWith({String? model, int? maxCtx, bool? disableThinking}) => OpenAiServer(
      baseUrl: baseUrl, apiKey: apiKey, model: model ?? this.model, kind: kind, maxCtx: maxCtx ?? this.maxCtx, disableThinking: disableThinking ?? this.disableThinking);
}

/// A model the built-in engine can download: one GGUF file on Hugging Face.
class BuiltinModel {
  const BuiltinModel(this.id, this.name, this.repo, this.file, this.sizeBytes, this.params, this.note, {this.thinks = false});
  final String id, name, repo, file, note;
  final int sizeBytes;
  final double params;

  /// Can think out loud before answering (Qwen3 hybrids): asked not to, so replies start quickly.
  final bool thinks;

  double get sizeGb => sizeBytes / 1e9;
  String get url => 'https://huggingface.co/$repo/resolve/main/$file';

  /// Memory it needs: the file, plus a little for running (each call's memory is added separately).
  double get needGb => sizeGb + 1.0;
  Fit fitFor(Hardware hw) => fitOf(needGb + kvCacheGb(params, 16384) * 2, hw.modelBudgetGb);
}

enum EngineRun { missing, stopped, starting, running, failed }

/// Working memory one call needs in a model of [params] billion parameters at [ctx] tokens (GB).
double kvCacheGb(double params, int ctx) {
  final kbPerToken = params <= 1 ? 12 : params <= 2 ? 30 : params <= 4.5 ? 80 : params <= 9 ? 140 : 200;
  return kbPerToken * ctx / 1e6;
}
