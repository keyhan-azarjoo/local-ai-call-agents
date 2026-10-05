import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/agent_loop.dart';
import 'package:localailine/services/mcp/mcp_client.dart';

ToolBinding tool(String name, String desc) => ToolBinding(
    serverId: 1,
    serverName: 'Shop',
    fnName: ToolBinding.safeName('Shop', name),
    tool: McpTool.fromJson({'name': name, 'description': desc, 'inputSchema': {'type': 'object', 'properties': {}}}));

void main() {
  test('read-only is inferred when the server gives no hint', () {
    expect(McpTool.inferReadOnly('list_users', 'List all users. Read-only.'), isTrue);
    expect(McpTool.inferReadOnly('get_order', 'Get one order by id.'), isTrue);
    expect(McpTool.inferReadOnly('update_user', 'Update a user. WRITES DATA.'), isFalse);
    expect(McpTool.inferReadOnly('merge', 'Merge two records. Read-only checks first. WRITES DATA.'), isFalse);
    expect(McpTool.inferReadOnly('send_invoice', 'Sends an invoice email.'), isFalse);
    // An explicit server hint always wins.
    final t = McpTool.fromJson({'name': 'list_x', 'description': 'Read-only.', 'annotations': {'readOnlyHint': false}});
    expect(t.readOnly, isFalse);
  });

  test('selector picks the relevant few out of many', () {
    final tools = [
      tool('list_users', 'List users of the shop. Read-only.'),
      tool('query_users', 'Flexible query over USERS. READ-ONLY.'),
      tool('create_user', 'Create a user. WRITES DATA.'),
      tool('list_orders', 'List orders. Read-only.'),
      tool('count_orders', 'Count orders without listing them. Read-only.'),
      tool('list_products', 'List products. Read-only.'),
      for (var i = 0; i < 60; i++) tool('admin_task_$i', 'Internal maintenance task number $i. WRITES DATA.'),
    ];
    final users = ToolSelector.rank('give me the list of users', tools, 5).map((t) => t.tool.name).toList();
    expect(users.take(2), containsAll(['list_users', 'query_users']));
    expect(users, isNot(contains('admin_task_1')));
    final count = ToolSelector.rank('how many orders do we have', tools, 3).map((t) => t.tool.name).toList();
    expect(count.first, 'count_orders');
    expect(ToolSelector.rank('xyzzy', tools, 5), isEmpty);
  });

  test('schemas are compacted and context sized to the request', () {
    final s = ToolLoop.compactSchema({
      r'$schema': 'x',
      'title': 'T',
      'type': 'object',
      'properties': {
        'a': {'type': 'string', 'description': 'word ' * 100, 'examples': ['1']}
      },
    }) as Map;
    expect(s.containsKey(r'$schema'), isFalse);
    expect((s['properties']['a']['description'] as String).length, lessThanOrEqualTo(201));
    expect(s['properties']['a'].containsKey('examples'), isFalse);
    expect(ToolLoop.ctxFor('x' * 1000, 32768), 8192);
    expect(ToolLoop.ctxFor('x' * 30000, 32768), 16384);
    expect(ToolLoop.ctxFor('x' * 300000, 16384), 16384);
  });

  test('typos and glued words still find the tool', () {
    expect(ToolSelector.near('eusers', 'users'), isTrue);
    expect(ToolSelector.near('elist', 'list'), isTrue);
    expect(ToolSelector.near('usres', 'users'), isFalse); // swapped letters: 2 edits
    expect(ToolSelector.near('scale', 'scales'), isTrue);
    expect(ToolSelector.near('cat', 'cats'), isFalse); // too short to guess
    final tools = [tool('list_users', 'List users. Read-only.'), tool('list_orders', 'List orders. Read-only.')];
    expect(ToolSelector.rank('give me th elist of th eusers', tools, 1).single.tool.name, 'list_users');
  });
}
