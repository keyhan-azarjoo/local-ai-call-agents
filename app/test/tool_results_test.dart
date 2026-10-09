import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/services/tool_results.dart';

String user(int i, String group, {bool big = false}) => const JsonEncoder.withIndent('  ').convert({
      'id': 'u$i',
      'firstName': 'Person',
      'lastName': '$i',
      'pictureUrl': '/Image?key=$i.jpg',
      'email': null,
      'phone': '',
      'groupIds': [group],
      'isActive': true,
      'isDeleted': false,
      if (big) 'access': {'grants': [for (var g = 0; g < 40; g++) {'resource': 'r$g', 'read': true, 'write': false}]},
    });

void main() {
  test('back-to-back JSON values become one compact list', () {
    final raw = [for (var i = 0; i < 6; i++) user(i, i < 4 ? 'g1' : 'g2')].join('\n');
    final r = ToolResults.compact(raw, 20000);
    expect(r.cut, isFalse);
    expect(r.text, startsWith('6 items:'));
    expect(r.text, isNot(contains('pictureUrl')));
    expect(r.text, isNot(contains('"email"')));
    expect(r.text.length, lessThan(raw.length));
  });

  test('ids get names from a lookup, and totals use the names', () {
    final raw = [for (var i = 0; i < 5; i++) user(i, i == 0 ? 'g2' : 'g1')].join('\n');
    final r = ToolResults.compact(raw, 20000, lookups: {'group': {'g1': 'Technician', 'g2': 'Supervisor'}});
    expect(r.text, contains('"groupNames":["Supervisor"]'));
    expect(r.text, contains('groupNames: Technician 4, Supervisor 1'));
  });

  test('a big item is shortened, not dropped', () {
    final raw = [for (var i = 0; i < 20; i++) user(i, 'g1', big: i == 19)].join('\n');
    final r = ToolResults.compact(raw, 3500);
    expect(r.cut, isFalse);
    expect(r.text, contains('Person'));
    expect(r.text, contains('"lastName":"19"'));
    expect(r.text, contains('entries]'));
  });

  test('when items really do not fit, the model is told how many are missing', () {
    final raw = jsonEncode([for (var i = 0; i < 200; i++) {'id': 'x$i', 'name': 'Item $i', 'notes': 'n' * 80}]);
    final r = ToolResults.compact(raw, 3000);
    expect(r.cut, isTrue);
    expect(r.text, startsWith('200 items:'));
    expect(r.text, contains('more did not fit'));
  });

  test('plain text is cut with a clear note', () {
    final r = ToolResults.compact('word ' * 2000, 1000);
    expect(r.cut, isTrue);
    expect(r.text, contains('INCOMPLETE'));
  });

  test('id names and referenced entities', () {
    expect(ToolResults.idNames(jsonEncode([{'id': 'a', 'name': 'Admins'}, {'_id': 'b', 'firstName': 'Ann', 'lastName': 'Lee'}])),
        {'a': 'Admins', 'b': 'Ann Lee'});
    expect(ToolResults.referencedEntities('{"groupIds": [1], "teamId": 2, "id": 3}'), {'group', 'team'});
  });
}
