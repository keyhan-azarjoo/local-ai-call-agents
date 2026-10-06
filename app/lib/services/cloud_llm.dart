import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ollama.dart' show ChatMessage;

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

class CloudError implements Exception {
  CloudError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calls the provider's own HTTP API directly. Nothing goes through any
/// LocalAILine server.
class CloudLlm {
  CloudLlm({http.Client? client}) : _c = client ?? http.Client();
  final http.Client _c;

  static const _azureApi = '2024-10-21';
  static const _anthropicVersion = '2023-06-01';

  String _azureBase(CloudConfig c) => c.endpoint.trim().replaceAll(RegExp(r'/+$'), '');

  /// Checks the key and returns the models the account can use, best guess first.
  /// For Azure, checks the endpoint + deployment with a one-word request.
  Future<List<String>> test(CloudConfig c) async {
    if (c.apiKey.trim().isEmpty) throw CloudError('Paste your API key first.');
    switch (c.provider) {
      case CloudProvider.openai:
        final r = await _c.get(Uri.parse('https://api.openai.com/v1/models'), headers: {'Authorization': 'Bearer ${c.apiKey}'});
        _check(r, 'OpenAI');
        final ids = ((jsonDecode(r.body) as Map)['data'] as List).map((m) => m['id'] as String).where(_isOpenAiChat).toList()..sort();
        return _preferred(ids, ['gpt-5-mini', 'gpt-5', 'gpt-4.1-mini', 'gpt-4o-mini', 'gpt-4o']);
      case CloudProvider.anthropic:
        final r = await _c.get(Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
            headers: {'x-api-key': c.apiKey, 'anthropic-version': _anthropicVersion});
        _check(r, 'Anthropic');
        final ids = ((jsonDecode(r.body) as Map)['data'] as List).map((m) => m['id'] as String).toList();
        return _preferred(ids, ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-4-5']);
      case CloudProvider.google:
        final r = await _c.get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
            headers: {'x-goog-api-key': c.apiKey});
        _check(r, 'Google');
        final ids = ((jsonDecode(r.body) as Map)['models'] as List)
            .where((m) => ((m['supportedGenerationMethods'] as List?) ?? []).contains('generateContent'))
            .map((m) => (m['name'] as String).replaceFirst('models/', ''))
            .where((id) => id.startsWith('gemini'))
            .toList()
          ..sort((a, b) => b.compareTo(a));
        return _preferred(ids, ids.where((i) => i.contains('flash') && !i.contains('lite')).take(1).toList());
      case CloudProvider.azure:
        if (c.endpoint.trim().isEmpty || c.model.trim().isEmpty) throw CloudError('Add the endpoint and the deployment name.');
        final r = await _c.post(
          Uri.parse('${_azureBase(c)}/openai/deployments/${c.model.trim()}/chat/completions?api-version=$_azureApi'),
          headers: {'api-key': c.apiKey, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'Say OK.'}
            ],
            'max_completion_tokens': 16,
          }),
        );
        _check(r, 'Azure');
        return [c.model.trim()];
    }
  }

  static bool _isOpenAiChat(String id) =>
      (id.startsWith('gpt-') || id.startsWith('o')) &&
      !RegExp(r'audio|realtime|tts|transcribe|image|search|embedding|instruct|moderation|codex').hasMatch(id);

  static List<String> _preferred(List<String> ids, List<String> prefs) {
    final first = prefs.where(ids.contains).toList();
    return [...first, ...ids.where((i) => !first.contains(i))];
  }

  void _check(http.Response r, String name) {
    if (r.statusCode == 200) return;
    final reason = switch (r.statusCode) {
      401 || 403 => 'the key was rejected',
      404 => 'not found — check the endpoint or deployment name',
      429 => 'rate limited or out of credit',
      _ => 'error ${r.statusCode}',
    };
    String detail = '';
    try {
      final j = jsonDecode(r.body);
      detail = (j['error']?['message'] ?? j['error'] ?? '').toString();
    } catch (_) {}
    throw CloudError('$name: $reason${detail.isEmpty ? '' : ' ($detail)'}');
  }

  /// Streams the reply text.
  Stream<String> chat(CloudConfig c, List<ChatMessage> messages) async* {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n\n');
    final turns = messages.where((m) => m.role != 'system').toList();
    late http.Request req;
    switch (c.provider) {
      case CloudProvider.openai:
      case CloudProvider.azure:
        final url = c.provider == CloudProvider.openai
            ? 'https://api.openai.com/v1/chat/completions'
            : '${_azureBase(c)}/openai/deployments/${c.model}/chat/completions?api-version=$_azureApi';
        req = http.Request('POST', Uri.parse(url))
          ..headers.addAll({
            'Content-Type': 'application/json',
            if (c.provider == CloudProvider.openai) 'Authorization': 'Bearer ${c.apiKey}' else 'api-key': c.apiKey,
          })
          ..body = jsonEncode({
            if (c.provider == CloudProvider.openai) 'model': c.model,
            'stream': true,
            'messages': [
              if (system.isNotEmpty) {'role': 'system', 'content': system},
              for (final m in turns)
                m.images.isEmpty
                    ? m.toJson()
                    : {
                        'role': m.role,
                        'content': [
                          {'type': 'text', 'text': m.content},
                          for (final i in m.images) {'type': 'image_url', 'image_url': {'url': 'data:${ChatMessage.mimeOf(i)};base64,$i'}},
                        ],
                      },
            ],
          });
      case CloudProvider.anthropic:
        req = http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
          ..headers.addAll({'Content-Type': 'application/json', 'x-api-key': c.apiKey, 'anthropic-version': _anthropicVersion})
          ..body = jsonEncode({
            'model': c.model,
            'max_tokens': 4096,
            'stream': true,
            // Phone calls need quick first words; low effort keeps thinking short.
            if (c.model.startsWith('claude-opus-5') || c.model.startsWith('claude-sonnet-5') || c.model.startsWith('claude-fable'))
              'output_config': {'effort': 'low'},
            if (system.isNotEmpty) 'system': system,
            'messages': [
              for (final m in turns)
                m.images.isEmpty
                    ? m.toJson()
                    : {
                        'role': m.role,
                        'content': [
                          for (final i in m.images) {'type': 'image', 'source': {'type': 'base64', 'media_type': ChatMessage.mimeOf(i), 'data': i}},
                          {'type': 'text', 'text': m.content},
                        ],
                      },
            ],
          });
      case CloudProvider.google:
        req = http.Request('POST',
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${c.model}:streamGenerateContent?alt=sse'))
          ..headers.addAll({'Content-Type': 'application/json', 'x-goog-api-key': c.apiKey})
          ..body = jsonEncode({
            if (system.isNotEmpty) 'systemInstruction': {'parts': [{'text': system}]},
            'contents': [
              for (final m in turns)
                {
                  'role': m.role == 'assistant' ? 'model' : 'user',
                  'parts': [
                    for (final i in m.images) {'inlineData': {'mimeType': ChatMessage.mimeOf(i), 'data': i}},
                    {'text': m.content},
                  ]
                }
            ],
          });
    }

    final res = await _c.send(req);
    if (res.statusCode != 200) {
      _check(http.Response(await res.stream.bytesToString(), res.statusCode), c.provider.label);
    }
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final j = jsonDecode(data) as Map<String, dynamic>;
      final piece = switch (c.provider) {
        CloudProvider.openai || CloudProvider.azure =>
          ((j['choices'] as List?)?.firstOrNull?['delta']?['content']) as String?,
        CloudProvider.anthropic => j['type'] == 'content_block_delta' && j['delta']?['type'] == 'text_delta'
            ? j['delta']['text'] as String?
            : j['type'] == 'error'
                ? throw CloudError('Anthropic: ${j['error']?['message']}')
                : null,
        CloudProvider.google => ((j['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?)
            ?.map((p) => p['text'] as String? ?? '')
            .join(),
      };
      if (piece != null && piece.isNotEmpty) yield piece;
    }
  }
}
