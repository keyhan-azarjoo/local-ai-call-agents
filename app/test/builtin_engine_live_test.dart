import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/agent_loop.dart';
import 'package:localailine/services/builtin_llm.dart';
import 'package:localailine/services/mcp/mcp_client.dart';
import 'package:localailine/services/ollama.dart' show ChatMessage;
import 'package:localailine/services/openai_compat.dart';

/// The built-in engine for real: starts llama.cpp's server on port 8940 with a small model, asks a
/// question that needs a tool, and stops it. Skipped when llama.cpp or the model file isn't there.
/// Model: LOCALAILINE_TEST_GGUF, or /tmp/llm-smoke/qwen05.gguf (Qwen2.5 0.5B Instruct Q4_K_M).
void main() {
  final gguf = Platform.environment['LOCALAILINE_TEST_GGUF'] ?? '/tmp/llm-smoke/qwen05.gguf';

  test('built-in engine: starts, answers with a tool call, stops', () async {
    final dir = await Directory.systemTemp.createTemp('ll_builtin_live');
    final e = BuiltinEngine(dataDir: dir.path);
    if (await e.binary() == null || !File(gguf).existsSync()) {
      markTestSkipped('llama-server or $gguf not found');
      return;
    }
    try {
      await e.start(gguf, lines: 1);
      expect(e.state, EngineRun.running, reason: e.problem);
      expect(await e.healthy(), isTrue);
      expect(await OpenAiCompat().models(e.server()), isNotEmpty);

      final weather = ToolBinding(
        serverId: 1,
        serverName: 'Weather',
        fnName: 'get_weather',
        tool: McpTool(
          name: 'get_weather',
          readOnly: true,
          description: 'Current weather for a city',
          inputSchema: {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
            'required': ['city'],
          },
        ),
      );
      final asked = <String>[];
      final loop = ToolLoop();
      final target = OpenAiTarget(e.server());
      final msgs = [
        ChatMessage('system', 'You answer weather questions. Always call get_weather first.'),
        ChatMessage('user', 'What is the weather in Paris right now?'),
      ];
      await loop.run(target: target, warmOnly: true, messages: msgs.sublist(0, 1), tools: [weather], approve: (_, _) async => true,
          runTool: (_, _) async => (text: '', isError: true));
      final answer = await loop.run(
        target: target,
        messages: msgs,
        tools: [weather],
        maxTokens: 200,
        approve: (_, _) async => true,
        runTool: (b, args) async {
          asked.add('${args['city']}');
          return (text: 'Paris: sunny, 21°C', isError: false);
        },
      );
      // ignore: avoid_print
      print('tool calls: $asked\nanswer: $answer');
      expect(asked, isNotEmpty);
      expect(asked.first.toLowerCase(), contains('paris'));
      expect(answer.trim(), isNotEmpty);
    } catch (_) {
      // ignore: avoid_print
      if (e.logFile.existsSync()) print(e.logFile.readAsLinesSync().reversed.take(30).toList().reversed.join('\n'));
      rethrow;
    } finally {
      await e.stop();
      await dir.delete(recursive: true);
    }
    expect(await e.healthy(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
