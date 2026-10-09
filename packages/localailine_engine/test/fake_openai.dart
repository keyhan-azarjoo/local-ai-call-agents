import 'dart:convert';
import 'dart:io';

/// A stand-in for the platform's OpenAI-compatible proxy: answers chat and embeddings, and
/// remembers what it was asked.
class FakeOpenAi {
  late HttpServer server;
  final chats = <Map<String, dynamic>>[];
  final embeds = <Map<String, dynamic>>[];
  final auth = <String?>[];

  /// The answer when JSON is asked for (building an app).
  String jsonAnswer = '{"questions": ["How many tables do you have?"]}';

  /// When set, the first request offering a tool whose name matches asks to use it, with a
  /// plain value for each required input.
  RegExp? useTool;
  String? usedTool;

  static Map<String, Object?> _argsFor(Map schema) => {
        for (final k in (schema['required'] as List?) ?? const [])
          '$k': switch (schema['properties']?[k]) {
            {'enum': List e} => e.first,
            {'type': 'integer' || 'number'} => 2,
            {'type': 'boolean'} => true,
            _ => 'Tom Smith',
          }
      };

  String get base => 'http://127.0.0.1:${server.port}/v1';

  static String _chunk(Map<String, Object?> delta, [String? finish]) => 'data: ${jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish}
        ]
      })}\n\n';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = (jsonDecode(await utf8.decodeStream(req)) as Map).cast<String, dynamic>();
      auth.add(req.headers.value('authorization'));
      final res = req.response..headers.contentType = ContentType.json;
      if (req.uri.path.endsWith('/embeddings')) {
        embeds.add(body);
        final input = body['input'] as List;
        res.write(jsonEncode({
          'data': [
            for (var i = 0; i < input.length; i++)
              {'index': i, 'embedding': List.generate(body['dimensions'] as int, (k) => (k == i % 8) ? 1.0 : 0.0)}
          ]
        }));
      } else {
        chats.add(body);
        final tool = usedTool == null && useTool != null
            ? [for (final t in (body['tools'] as List?) ?? const []) t['function'] as Map].where((f) => useTool!.hasMatch('${f['name']}')).firstOrNull
            : null;
        final words = body['response_format'] != null ? [jsonAnswer] : ['Hello', ' from', ' the', ' cloud.'];
        if (body['stream'] == true) {
          res.headers.contentType = ContentType('text', 'event-stream');
          if (tool != null) {
            usedTool = '${tool['name']}';
            res.write(_chunk({
              'tool_calls': [
                {'index': 0, 'id': 'call_1', 'type': 'function', 'function': {'name': usedTool, 'arguments': jsonEncode(_argsFor(tool['parameters'] as Map? ?? const {}))}}
              ]
            }, 'tool_calls'));
          } else {
            for (final w in words) {
              res.write(_chunk({'content': w}));
            }
          }
          res.write('data: [DONE]\n\n');
        } else {
          res.write(jsonEncode({
            'choices': [
              {'index': 0, 'message': {'role': 'assistant', 'content': words.join()}, 'finish_reason': 'stop'}
            ]
          }));
        }
      }
      await res.close();
    });
  }
}
