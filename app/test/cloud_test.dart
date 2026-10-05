import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:localailine/services/cloud_llm.dart';
import 'package:localailine/services/ollama.dart' show ChatMessage;

/// Fake provider servers: check what we send, answer like the real API.
http.Client fake(void Function(http.BaseRequest) check, String body, {int status = 200}) =>
    MockClient.streaming((req, bodyStream) async {
      check(req);
      return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
    });

final msgs = [ChatMessage('system', 'Be brief.'), ChatMessage('user', 'Hi')];

void main() {
  test('OpenAI: lists chat models, preferred first, and streams deltas', () async {
    var llm = CloudLlm(client: fake((r) {
      expect(r.url.toString(), 'https://api.openai.com/v1/models');
      expect(r.headers['Authorization'], 'Bearer k');
    }, jsonEncode({'data': [{'id': 'whisper-1'}, {'id': 'gpt-4o'}, {'id': 'gpt-4o-mini'}, {'id': 'gpt-4o-realtime-preview'}]})));
    final models = await llm.test(CloudConfig(provider: CloudProvider.openai, apiKey: 'k'));
    expect(models, ['gpt-4o-mini', 'gpt-4o']);

    llm = CloudLlm(client: fake((r) {
      final b = jsonDecode((r as http.Request).body);
      expect(b['model'], 'gpt-4o-mini');
      expect(b['messages'][0], {'role': 'system', 'content': 'Be brief.'});
    }, 'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\ndata: {"choices":[{"delta":{"content":"lo"}}]}\n\ndata: [DONE]\n\n'));
    expect(await llm.chat(CloudConfig(provider: CloudProvider.openai, apiKey: 'k', model: 'gpt-4o-mini'), msgs).join(), 'Hello');
  });

  test('Azure: deployment URL, api-key header', () async {
    final llm = CloudLlm(client: fake((r) {
      expect(r.url.toString(), startsWith('https://res.openai.azure.com/openai/deployments/dep1/chat/completions?api-version='));
      expect(r.headers['api-key'], 'k');
    }, 'data: {"choices":[{"delta":{"content":"OK"}}]}\n\n'));
    final c = CloudConfig(provider: CloudProvider.azure, apiKey: 'k', endpoint: 'https://res.openai.azure.com/', model: 'dep1');
    expect(await llm.chat(c, msgs).join(), 'OK');
  });

  test('Anthropic: headers, system separate, text deltas only', () async {
    final llm = CloudLlm(client: fake((r) {
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(r.headers['x-api-key'], 'k');
      expect(r.headers['anthropic-version'], '2023-06-01');
      final b = jsonDecode((r as http.Request).body);
      expect(b['system'], 'Be brief.');
      expect((b['messages'] as List).length, 1);
    }, [
      'event: message_start\ndata: {"type":"message_start"}\n',
      'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}\n',
      'event: content_block_delta\ndata: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi there"}}\n',
      'event: message_stop\ndata: {"type":"message_stop"}\n',
    ].join('\n')));
    expect(await llm.chat(CloudConfig(provider: CloudProvider.anthropic, apiKey: 'k', model: 'claude-opus-5-5'), msgs).join(), 'Hi there');
  });

  test('Google: key header, roles mapped, parts joined', () async {
    final llm = CloudLlm(client: fake((r) {
      expect(r.url.path, endsWith('models/gemini-x:streamGenerateContent'));
      expect(r.headers['x-goog-api-key'], 'k');
      final b = jsonDecode((r as http.Request).body);
      expect(b['systemInstruction']['parts'][0]['text'], 'Be brief.');
      expect(b['contents'][0]['role'], 'user');
    }, 'data: {"candidates":[{"content":{"parts":[{"text":"Hey"}]}}]}\n\n'));
    expect(await llm.chat(CloudConfig(provider: CloudProvider.google, apiKey: 'k', model: 'gemini-x'), msgs).join(), 'Hey');
  });

  test('bad key gives a plain message', () async {
    final llm = CloudLlm(client: fake((_) {}, jsonEncode({'error': {'message': 'Invalid API key'}}), status: 401));
    expect(
      () => llm.test(CloudConfig(provider: CloudProvider.openai, apiKey: 'bad')),
      throwsA(isA<CloudError>().having((e) => e.message, 'message', contains('the key was rejected'))),
    );
    expect(() => llm.test(CloudConfig(provider: CloudProvider.openai, apiKey: '')), throwsA(isA<CloudError>()));
  });
}
