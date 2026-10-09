import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/agent_loop.dart';
import 'package:localailine_core/services/builtin_llm.dart';
import 'package:localailine_core/services/catalog.dart';
import 'package:localailine_core/services/cloud_llm.dart';
import 'package:localailine_core/services/hardware.dart';
import 'package:localailine_core/services/mcp/mcp_client.dart';
import 'package:localailine_core/services/ollama.dart' show ChatMessage;
import 'package:localailine_core/services/openai_compat.dart';

/// A tiny OpenAI-compatible server (like llama.cpp's or vLLM's): each chat request is answered
/// with the next scripted reply, streamed as SSE chunks. Requests are kept to check what we sent.
class FakeServer {
  late HttpServer _s;
  final requests = <Map<String, dynamic>>[];
  final headers = <HttpHeaders>[];

  /// Each reply: the `data:` payloads to stream (maps are JSON-encoded), in order.
  final replies = <List<Object>>[];
  Duration gap = Duration.zero;

  String get base => 'http://127.0.0.1:${_s.port}/v1';

  Future<void> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((rq) async {
      headers.add(rq.headers);
      if (rq.uri.path == '/v1/models') {
        rq.response.headers.contentType = ContentType.json;
        rq.response.write(jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'qwen3-4b'},
            {'id': 'nomic-embed-text'},
            {'id': 'llama-3.2-3b'},
          ]
        }));
        await rq.response.close();
        return;
      }
      final body = jsonDecode(await utf8.decodeStream(rq)) as Map<String, dynamic>;
      requests.add(body);
      final chunks = replies.isEmpty ? <Object>[] : replies.removeAt(0);
      if (body['stream'] == false) {
        // Not streamed: the whole message at once (warm-ups, order totals).
        final text = chunks.whereType<Map>().map((c) => (c['choices'] as List).first['delta']?['content'] ?? '').join();
        rq.response.headers.contentType = ContentType.json;
        rq.response.write(jsonEncode({
          'choices': [
            {'index': 0, 'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': text}}
          ]
        }));
        await rq.response.close();
        return;
      }
      rq.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      rq.response.bufferOutput = false;
      for (final c in chunks) {
        rq.response.write('data: ${c is String ? c : jsonEncode(c)}\n\n');
        await rq.response.flush();
        if (gap > Duration.zero) await Future.delayed(gap);
      }
      rq.response.write('data: [DONE]\n\n');
      await rq.response.close();
    });
  }

  Future<void> stop() => _s.close(force: true);
}

Map<String, Object> text(String t, {String? finish}) => {
      'choices': [
        {'index': 0, 'delta': {'content': t}, 'finish_reason': ?finish}
      ]
    };

Map<String, Object> call(int i, {String? id, String? name, String? args, String? finish}) => {
      'choices': [
        {
          'index': 0,
          'delta': {
            'tool_calls': [
              {
                'index': i,
                'id': ?id,
                if (id != null) 'type': 'function',
                'function': {'name': ?name, 'arguments': ?args},
              }
            ]
          },
          'finish_reason': ?finish,
        }
      ]
    };

Map<String, Object> finish(String why) => {
      'choices': [
        {'index': 0, 'delta': <String, Object>{}, 'finish_reason': why}
      ]
    };

final weather = ToolBinding(
  serverId: 1,
  serverName: 'Weather',
  fnName: 'weather__get_weather',
  tool: McpTool(
    name: 'get_weather',
    readOnly: true,
    description: 'Weather for a city',
    inputSchema: {
      'type': 'object',
      'properties': {'city': {'type': 'string'}},
      'required': ['city'],
    },
  ),
);

Hardware hw(double ram) => Hardware(os: 'test', cpu: 'cpu', cores: 8, ramGb: ram, gpu: 'gpu', vramGb: 0, unifiedMemory: true, freeDiskGb: 100);

void main() {
  late FakeServer srv;
  setUp(() async {
    srv = FakeServer();
    await srv.start();
  });
  tearDown(() => srv.stop());

  OpenAiServer server({String key = ''}) => OpenAiServer(baseUrl: srv.base, apiKey: key, model: 'qwen3-4b');

  group('OpenAI-compatible server', () {
    test('address: /v1 added, trailing slash and /chat/completions removed', () {
      expect(OpenAiServer(baseUrl: 'http://127.0.0.1:8000').base, 'http://127.0.0.1:8000/v1');
      expect(OpenAiServer(baseUrl: '127.0.0.1:1234/v1/').base, 'http://127.0.0.1:1234/v1');
      expect(OpenAiServer(baseUrl: 'http://h:8080/v1/chat/completions').base, 'http://h:8080/v1');
    });

    test('lists models (not embedding ones) with the key', () async {
      final ids = await OpenAiCompat().models(server(key: 'sk-1'));
      expect(ids, ['qwen3-4b', 'llama-3.2-3b']);
      expect(srv.headers.last.value('authorization'), 'Bearer sk-1');
    });

    test('unreachable server: a plain message', () async {
      await expectLater(OpenAiCompat().models(OpenAiServer(baseUrl: 'http://127.0.0.1:1/v1')), throwsA(isA<CloudError>()));
    });

    test('streams text; thinking is left out; json mode and no-thinking are asked for', () async {
      srv.replies.add([text('<think>hmm'), text(' let me see</think>'), text('Hel'), text('lo!', finish: 'stop')]);
      final s = OpenAiServer(baseUrl: srv.base, model: 'm', disableThinking: true);
      final pieces = await OpenAiCompat().chat(s, [ChatMessage('system', 'Be brief.'), ChatMessage('user', 'Hi')], json: true, temperature: .2).toList();
      expect(pieces.join(), 'Hello!');
      final b = srv.requests.single;
      expect(b['stream'], true);
      expect(b['model'], 'm');
      expect(b['response_format'], {'type': 'json_object'});
      expect(b['chat_template_kwargs'], {'enable_thinking': false});
      expect(b['messages'][0], {'role': 'system', 'content': 'Be brief.'});
    });

    test('server error comes back as a plain message', () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((rq) async {
        rq.response.statusCode = 400;
        rq.response.write(jsonEncode({'error': {'message': 'the request exceeds the available context size'}}));
        await rq.response.close();
      });
      final o = OpenAiServer(baseUrl: 'http://127.0.0.1:${s.port}/v1', model: 'm');
      await expectLater(OpenAiCompat().chat(o, [ChatMessage('user', 'Hi')]).toList(),
          throwsA(isA<CloudError>().having((e) => e.message, 'message', contains('context size'))));
      await s.close(force: true);
    });
  });

  group('reply assembly', () {
    test('tool calls in pieces across chunks, two calls, finish reason', () {
      final r = StreamedReply();
      for (final c in [
        call(0, id: 'a1', name: 'get_weather', args: ''),
        call(0, args: '{"ci'),
        call(1, id: 'b2', name: 'calc', args: '{"expression":'),
        call(0, args: 'ty": "Paris"}'),
        call(1, args: ' "2+2"}'),
        finish('tool_calls'),
      ]) {
        r.add('data: ${jsonEncode(c)}');
      }
      expect(r.finishReason, 'tool_calls');
      expect(r.toolCalls, [
        {'id': 'a1', 'type': 'function', 'function': {'name': 'get_weather', 'arguments': '{"city": "Paris"}'}},
        {'id': 'b2', 'type': 'function', 'function': {'name': 'calc', 'arguments': '{"expression": "2+2"}'}},
      ]);
      expect(r.cutOff, isFalse);
    });

    test('length cap is noticed; other lines ignored; errors thrown', () {
      final r = StreamedReply()
        ..add(': keep-alive')
        ..add('data: [DONE]')
        ..add('data: ${jsonEncode(text('abc', finish: 'length'))}');
      expect(r.cutOff, isTrue);
      expect(r.answer, 'abc');
      expect(() => StreamedReply().add('data: {"error":{"message":"boom"}}'), throwsA(isA<CloudError>()));
    });
  });

  group('tool loop on an OpenAI-compatible server', () {
    test('runs the tools asked for (assembled across chunks), then streams the answer', () async {
      srv.gap = const Duration(milliseconds: 5);
      srv.replies
        ..add([
          call(0, id: 'c1', name: 'weather__get_weather', args: '{"ci'),
          call(1, id: 'c2', name: 'calculate', args: '{"expression": "2*'),
          call(0, args: 'ty":"Paris"}'),
          call(1, args: '16 + 3.95"}'),
          finish('tool_calls'),
        ])
        ..add([text('It is '), text('sunny in Paris; '), text('total £35.95.'), finish('stop')]);
      final ran = <String>[];
      final shown = <String>[];
      final answer = await ToolLoop().run(
        target: OpenAiTarget(server()),
        messages: [ChatMessage('system', 'You help.'), ChatMessage('user', 'Weather in Paris, and what is 2*16+3.95?')],
        tools: [weather],
        maxTokens: 321,
        approve: (_, _) async => true,
        runTool: (b, args) async {
          ran.add('${b.tool.name} ${args['city']}');
          return (text: 'Sunny, 21C', isError: false);
        },
        onText: shown.add,
      );
      expect(answer, 'It is sunny in Paris; total £35.95.');
      expect(ran, ['get_weather Paris']);
      expect(shown.last, answer);
      expect(shown.length, greaterThan(1)); // streamed, not all at once

      final first = srv.requests[0], second = srv.requests[1];
      expect(first['max_tokens'], 321);
      expect(first['stream'], true);
      expect((first['tools'] as List).map((t) => t['function']['name']), containsAll(['calculate', 'weather__get_weather']));
      // The second request repeats the first exactly, then adds the calls and their results (prefix reuse).
      expect(jsonEncode((second['messages'] as List).take((first['messages'] as List).length).toList()), jsonEncode(first['messages']));
      final added = (second['messages'] as List).skip((first['messages'] as List).length).toList();
      expect(added[0]['role'], 'assistant');
      expect((added[0]['tool_calls'] as List).length, 2);
      expect(added[1], {'role': 'tool', 'tool_call_id': 'c1', 'content': contains('Sunny')});
      expect(added[2]['tool_call_id'], 'c2');
      expect(added[2]['content'], contains('35.95'));
    });

    test('a tool call cut off at the length cap is asked for again', () async {
      srv.replies
        ..add([call(0, id: 'x', name: 'weather__get_weather', args: '{"city": "Par'), finish('length')])
        ..add([call(0, id: 'y', name: 'weather__get_weather', args: '{"city":"Rome"}'), finish('tool_calls')])
        ..add([text('Rome is warm.'), finish('stop')]);
      final ran = <String>[];
      final answer = await ToolLoop().run(
        target: OpenAiTarget(server()),
        messages: [ChatMessage('user', 'Weather in Rome?')],
        tools: [weather],
        approve: (_, _) async => true,
        runTool: (b, args) async {
          ran.add('${args['city']}');
          return (text: 'Warm', isError: false);
        },
      );
      expect(answer, 'Rome is warm.');
      expect(ran, ['Rome']);
      expect((srv.requests[1]['messages'] as List).last['content'], contains('was cut off'));
    });

    test('warm-up reads the prompt and tools without answering', () async {
      final out = await ToolLoop().run(
        target: OpenAiTarget(server()),
        warmOnly: true,
        messages: [ChatMessage('system', 'You help.')],
        tools: [weather],
        approve: (_, _) async => false,
        runTool: (_, _) async => (text: '', isError: true),
      );
      expect(out, '');
      expect(srv.requests.single['max_tokens'], 1);
      expect(srv.requests.single['stream'], false);
      expect(srv.requests.single['tools'], isNotEmpty);
    });

    test('cancelled while the answer streams: stops', () async {
      srv.gap = const Duration(milliseconds: 20);
      srv.replies.add([for (var i = 0; i < 50; i++) text('word ')]);
      var seen = 0;
      await expectLater(
        ToolLoop().run(
          target: OpenAiTarget(server()),
          messages: [ChatMessage('user', 'Talk')],
          tools: const [],
          approve: (_, _) async => false,
          runTool: (_, _) async => (text: '', isError: true),
          onText: (_) {
            if (++seen == 3) throw const Cancelled();
          },
        ),
        throwsA(isA<Cancelled>()),
      );
      expect(seen, 3);
    });

    test('it counts as a local model: few tools, order totals worked out by the app', () async {
      expect(OpenAiTarget(server()).isLocal, isTrue);
      expect(LocalTarget('x').isLocal, isTrue);
      expect(CloudTarget(CloudConfig(provider: CloudProvider.openai, apiKey: 'k')).isLocal, isFalse);
      srv.replies.add([text('{"is_order": true, "lines": [{"line": 1, "quantity": 2}]}')]);
      final q = await OrderQuote.quote(ToolLoop().client, OpenAiTarget(server()), [ChatMessage('user', 'Two fish and chips please')], ['Fish & chips £16.00']);
      expect(q, contains('TOTAL £32.00'));
      expect(srv.requests.single['response_format']['type'], 'json_schema');
    });
  });

  group('built-in engine', () {
    test('command line sized from the calls at the same time', () {
      final a = BuiltinEngine.args(model: '/m/q.gguf', lines: 3, ctxPerSlot: 16384);
      String after(String flag) => a[a.indexOf(flag) + 1];
      expect(after('-m'), '/m/q.gguf');
      expect(after('--port'), '8940');
      expect(after('--host'), '127.0.0.1');
      expect(after('-np'), '4'); // one per call plus a spare
      expect(after('-c'), '${16384 * 4}');
      expect(after('--cache-ram'), '1536');
      expect(after('--cache-type-k'), 'q8_0');
      expect(after('--cache-type-v'), 'q8_0');
      expect(after('-fa'), 'on');
      expect(a, contains('--jinja'));
      expect(BuiltinEngine.args(model: 'm', lines: 1, ctxPerSlot: 8192), containsAllInOrder(['-c', '16384', '-np', '2']));
    });

    test('each call gets 16k when memory allows, less on small computers', () {
      expect(BuiltinEngine.ctxPerSlotFor(budgetGb: 11, modelGb: 2.5, params: 4, slots: 3), 16384);
      expect(BuiltinEngine.ctxPerSlotFor(budgetGb: 4, modelGb: 2.5, params: 4, slots: 2), lessThan(16384));
      expect(BuiltinEngine.ctxPerSlotFor(budgetGb: 2, modelGb: 2.5, params: 4, slots: 2), 4096);
    });

    test('suggested model fits the computer', () {
      expect(BuiltinEngine.recommend(hw(18)).id, 'qwen3-4b-instruct-2507');
      expect(BuiltinEngine.recommend(hw(8)).params, lessThanOrEqualTo(4));
      expect(BuiltinEngine.byId('qwen3-8b')!.fitFor(hw(8)), Fit.tooLarge);
      for (final m in BuiltinEngine.catalog) {
        expect(m.url, startsWith('https://huggingface.co/'));
        expect(m.file, endsWith('.gguf'));
      }
    });

    test('Hugging Face links in their usual shapes', () {
      expect(BuiltinEngine.hfUrl('https://huggingface.co/org/repo/blob/main/m-Q4_K_M.gguf').toString(), 'https://huggingface.co/org/repo/resolve/main/m-Q4_K_M.gguf');
      expect(BuiltinEngine.hfUrl('hf.co/org/repo/resolve/main/m.gguf?download=true').toString(), 'https://huggingface.co/org/repo/resolve/main/m.gguf');
      expect(BuiltinEngine.hfUrl('https://example.com/m.gguf'), isNull);
      expect(BuiltinEngine.hfUrl('https://huggingface.co/org/repo'), isNull);
    });

    test('finds models downloaded with Ollama', () async {
      final d = await Directory.systemTemp.createTemp('ll_ollama');
      final man = Directory('${d.path}/manifests/registry.ollama.ai/library/qwen3')..createSync(recursive: true);
      File('${d.path}/blobs/sha256-abc').createSync(recursive: true);
      File('${man.path}/4b').writeAsStringSync(jsonEncode({
        'layers': [
          {'mediaType': 'application/vnd.ollama.image.model', 'digest': 'sha256:abc'},
          {'mediaType': 'application/vnd.ollama.image.template', 'digest': 'sha256:def'},
        ]
      }));
      expect(BuiltinEngine.ollamaModels(home: d.path), {'qwen3:4b': '${d.path}/blobs/sha256-abc'});
      await d.delete(recursive: true);
    });

    test('downloads a model file with progress, refuses a page that is not one', () async {
      final d = await Directory.systemTemp.createTemp('ll_builtin');
      final files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      files.listen((rq) async {
        final good = rq.uri.path.endsWith('good.gguf');
        final bytes = good ? [...utf8.encode('GGUF'), ...List.filled(200000, 7)] : utf8.encode('<html>not found</html>');
        rq.response.contentLength = bytes.length;
        rq.response.add(bytes);
        await rq.response.close();
      });
      final e = BuiltinEngine(dataDir: d.path);
      final p = await e.download(Uri.parse('http://127.0.0.1:${files.port}/good.gguf'), 'good.gguf').toList();
      expect(p.last, 1);
      expect(e.pathFor('good.gguf'), endsWith('good.gguf'));
      expect(e.localFiles().length, 1);
      await expectLater(e.download(Uri.parse('http://127.0.0.1:${files.port}/bad.gguf'), 'bad.gguf').toList(), throwsA(isA<Exception>()));
      expect(e.pathFor('bad.gguf'), isNull);
      await files.close(force: true);
      await d.delete(recursive: true);
    });
  });

  group('settings', () {
    test('round-trip; a choice that cannot work falls back to Ollama', () async {
      final tmp = await Directory.systemTemp.createTemp('ll_llm');
      final db = await Db.open(path: '${tmp.path}/t.db');
      expect((await LlmSettings.load(db)).source, 'local'); // unchanged default

      await LlmSettings(
        source: 'openai',
        server: OpenAiServer(baseUrl: 'http://127.0.0.1:8000/v1', apiKey: 'k', model: 'qwen', kind: ServerKind.vllm, maxCtx: 8192, disableThinking: true),
        builtinModel: 'qwen3-4b-instruct-2507',
      ).save(db);
      final l = await LlmSettings.load(db);
      expect(l.source, 'openai');
      expect(l.server!.toJson(), {'baseUrl': 'http://127.0.0.1:8000/v1', 'apiKey': 'k', 'model': 'qwen', 'kind': 'vllm', 'maxCtx': 8192, 'disableThinking': true});
      expect(l.builtinModel, 'qwen3-4b-instruct-2507');

      await db.setSetting('llm.openai', '');
      expect((await LlmSettings.load(db)).source, 'local');
      await db.setSetting('llm.source', 'builtin');
      expect((await LlmSettings.load(db)).source, 'builtin');
      await db.raw.close();
      await tmp.delete(recursive: true);
    });

    test('LOCALAILINE_LLM override', () {
      final o = LlmOverride.parse('ollama:qwen3:4b-instruct')!;
      expect([o.source, o.value], ['local', 'qwen3:4b-instruct']);
      final b = LlmOverride.parse('builtin:qwen2.5-0.5b-instruct')!;
      expect([b.source, b.value], ['builtin', 'qwen2.5-0.5b-instruct']);
      final s = LlmOverride.parse('openai:http://127.0.0.1:8000/v1|Qwen/Qwen3-8B')!;
      expect([s.source, s.value, s.model], ['openai', 'http://127.0.0.1:8000/v1', 'Qwen/Qwen3-8B']);
      expect(LlmOverride.parse('nonsense'), isNull);
      expect(LlmOverride.parse(''), isNull);
      expect(LlmOverride.parse(null), isNull);
    });
  });
}
