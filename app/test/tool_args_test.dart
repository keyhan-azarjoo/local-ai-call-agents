import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/services/tool_args.dart';

final schema = {
  'type': 'object',
  'properties': {
    'team_id': {'type': 'string', 'description': 'Team id.'},
    'is_active': {'anyOf': [{'type': 'boolean'}, {'type': 'null'}]},
    'limit': {'type': 'integer'},
    'date_from': {'anyOf': [{'type': 'string'}, {'type': 'null'}]},
    'stage': {'enum': ['in', 'out']},
    'name': {'anyOf': [{'type': 'string'}, {'type': 'null'}]},
  },
  'required': ['team_id'],
};
final now = DateTime(2026, 10, 5);

void main() {
  test('types are fixed, empty optionals dropped, dates in words converted', () {
    final r = ToolArgs.prepare(schema, {'team_id': '69f36bdce5415be4b7dc5a70', 'is_active': 'yes', 'limit': '10', 'date_from': 'last month', 'stage': 'OUT', 'name': ''}, now: now);
    expect(r.problem, isNull);
    expect(r.args, {'team_id': '69f36bdce5415be4b7dc5a70', 'is_active': true, 'limit': 10, 'date_from': '2026-09-01', 'stage': 'out'});
  });

  test('names or made-up ids are refused before calling the server, with a lookup tip', () {
    final mem = IdMemory()..learn('{"id": "69f36bdce5415be4b7dc5a70"}');
    String? tool(String e) => e == 'team' ? 'list_teams' : null;
    var r = ToolArgs.prepare(schema, {'team_id': 'Aston Martin F1'}, now: now, lookupToolFor: tool, toolName: 'count_parts');
    expect(r.problem, contains('list_teams'));
    expect(r.problem, contains('call count_parts again'));
    r = ToolArgs.prepare(schema, {'team_id': '65d1a3b2c3d4e5f678901234'}, now: now, lookupToolFor: tool, looksWrongId: (k, v) => mem.looksWrong(v, canLookUp: true));
    expect(r.problem, contains('not seen'));
    r = ToolArgs.prepare(schema, {'team_id': '69f36bdce5415be4b7dc5a70'}, now: now, lookupToolFor: tool, looksWrongId: (k, v) => mem.looksWrong(v, canLookUp: true));
    expect(r.problem, isNull);
  });

  test('missing required input and bad enum are explained', () {
    expect(ToolArgs.prepare(schema, {}, now: now).problem, contains('Missing required input `team_id`'));
    expect(ToolArgs.prepare(schema, {'team_id': 'x123456789', 'stage': 'sideways'}, now: now).problem, contains('must be one of: in, out'));
    expect(ToolArgs.prepare(schema, {'team_id': 'x123456789', 'date_from': 'whenever'}, now: now).problem, contains('must be a date like 2026-10-05'));
  }, skip: false);

  test('natural dates', () {
    expect(ToolArgs.naturalDate('yesterday', now), DateTime(2026, 10, 4));
    expect(ToolArgs.naturalDate('3 days ago', now), DateTime(2026, 10, 2));
    expect(ToolArgs.naturalDate('this week', now), DateTime(2026, 10, 5));
    expect(ToolArgs.naturalDate('last year', now), DateTime(2025));
  });

  test('server errors become short, clear messages without internal addresses', () {
    final e = ToolErrors.friendly('Error executing tool get_team: HTTP 500 on http://host.docker.internal:8585/Team/id?id=X: '
        '{"success":false,"data":null,"message":"\'X\' is not a valid 24 digit hex string.","errorCode":"SERVER_ERROR"}');
    expect(e, startsWith('Tool error (500):'));
    expect(e, contains('not a valid 24 digit hex string'));
    expect(e, isNot(contains('docker.internal')));
    final v = ToolErrors.friendly('Error executing tool count_parts: 1 validation error for count_partsArguments\nteam_id\n  Field required [type=missing]');
    expect(v, contains('Missing required input: team_id'));
    expect(ToolErrors.friendly('HTTP 404 on http://x/y: {"message":"User not found."}'), contains('Nothing was found'));
    expect(ToolErrors.looksLikeError('Error executing tool x: boom'), isTrue);
    expect(ToolErrors.looksLikeError('{"ok": true}'), isFalse);
  });
}
