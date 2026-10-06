import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_builder.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_server.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/mcp/mcp_client.dart';
import 'package:localailine/services/ollama.dart';

/// A restaurant, the way a small model might describe it (with mistakes to repair).
final restaurant = {
  'name': 'Luigi’s',
  'summary': 'Menu, orders and tables.',
  'tables': [
    {
      'id': 'Menu Items',
      'purpose': 'food and prices',
      'access': 'see',
      'fields': [
        {'id': 'name', 'type': 'string', 'required': true},
        {'id': 'price', 'type': 'price'},
        {'id': 'category', 'type': 'enum', 'options': 'Pizza, Pasta, Drinks'},
      ],
    },
    {
      'id': 'tables',
      'access': 'none',
      'fields': [
        {'id': 'number', 'type': 'text'},
        {'id': 'seats', 'type': 'int'},
      ],
    },
    {
      'id': 'orders',
      'access': 'add',
      'fields': [
        {'id': 'customer', 'type': 'text', 'required': true},
        {'id': 'table', 'type': 'reference', 'link': 'table'},
        {'id': 'items', 'type': 'links', 'link': 'menu_item', 'qty': true},
        {'id': 'status', 'type': 'choice', 'options': ['New', 'Cooking', 'Served'], 'manager_only': true},
        {'id': 'ghost', 'type': 'link', 'link': 'nowhere'},
      ],
    },
    {
      'id': 'hours',
      'kind': 'single',
      'access': 'see',
      'fields': [
        {'id': 'open', 'type': 'time'},
        {'id': 'close', 'type': 'time'},
      ],
    },
  ],
  'pages': [
    {
      'id': 'order',
      'blocks': [
        'Welcome!',
        {'type': 'cards', 'table': 'menu_items'},
        {'type': 'form', 'table': 'orders', 'submit': 'Order'},
        {'type': 'list', 'table': 'hours'},
        {'type': 'list', 'table': 'nope'},
        {'type': 'weird'},
      ],
    },
  ],
};

void main() {
  group('spec repair', () {
    final spec = AppSpec.fromJson(restaurant);

    test('ids, types and links are cleaned up', () {
      expect(spec.tables.map((t) => t.id), ['menu_items', 'tables', 'orders', 'hours']);
      final menu = spec.table('menu_items')!;
      expect(menu.fields.map((f) => f.type), ['text', 'money', 'choice']);
      expect(menu.field('category')!.options, ['Pizza', 'Pasta', 'Drinks']);
      final orders = spec.table('orders')!;
      expect(orders.field('table')!.type, 'link');
      expect(orders.field('table')!.link, 'tables');
      expect(orders.field('items')!.link, 'menu_items');
      expect(orders.field('ghost')!.type, 'text', reason: 'links to a missing table become text');
      expect(spec.table('hours')!.single, isTrue);
    });

    test('customers can pick the tables an order links to', () {
      expect(spec.table('tables')!.access.see, isTrue);
    });

    test('blocks: unknown ones dropped, list of a single table becomes info', () {
      final blocks = spec.page('order')!.blocks;
      expect(blocks.map((b) => b.type), ['text', 'list', 'form', 'info']);
    });

    test('round trip', () {
      expect(AppSpec.fromJson(jsonDecode(jsonEncode(spec.toJson()))).toJson(), spec.toJson());
    });

    test('parseJson tolerates fences and trailing commas', () {
      expect(AppBuilder.parseJson('Sure!\n```json\n{"a": [1, 2,],}\n```'), {'a': [1, 2]});
      expect(AppBuilder.parseJson('no json'), isNull);
    });
  });

  group('running app', () {
    late Db db;
    late Directory tmp;
    late AppServer server;
    late String base;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('apps');
      db = await Db.open(path: '${tmp.path}/t.db');
      final now = DateTime.now().millisecondsSinceEpoch;
      final spec = AppSpec.fromJson(restaurant);
      final id = await db.insert('apps', {'name': spec.name, 'request': 'x', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': '123456', 'created_at': now, 'updated_at': now});
      final data = AppData(db, id, spec);
      await data.add('menu_items', {'name': 'Margherita', 'price': '9.5', 'category': 'pizza'}, manager: true);
      await data.add('menu_items', {'name': 'Carbonara', 'price': 12, 'category': 'Pasta'}, manager: true);
      await data.add('tables', {'number': 'T1', 'seats': 4}, manager: true);
      await data.setSingle('hours', {'open': '12:00', 'close': '22:00'});
      server = AppServer(data: data, pin: '123456');
      await server.start(0);
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.stop();
      await db.raw.close();
      tmp.deleteSync(recursive: true);
    });

    test('website and public API follow the access rules', () async {
      expect((await http.get(Uri.parse('$base/'))).body, contains('/app.js'));
      final menu = jsonDecode((await http.get(Uri.parse('$base/api/t/menu_items?q=pizza'))).body) as List;
      expect(menu.single['name'], 'Margherita');
      expect(menu.single['price'], 9.5);
      expect((await http.get(Uri.parse('$base/api/t/orders'))).statusCode, 403, reason: 'customers cannot see orders');
      final add = await http.post(Uri.parse('$base/api/t/orders'),
          body: jsonEncode({'customer': 'Ann', 'table': 'T1', 'items': [{'id': 'margherita', 'qty': 2}], 'status': 'Served'}));
      expect(add.statusCode, 200, reason: add.body);
      final mine = jsonDecode((await http.get(Uri.parse('$base/api/t/orders'), headers: {'X-Key': '123456'})).body) as List;
      expect(mine.single['status'], 'New', reason: 'customers cannot set manager-only fields');
      expect(mine.single['items'], [{'id': 1, 'qty': 2}]);
      expect((await http.delete(Uri.parse('$base/api/t/menu_items/1'))).statusCode, 403);
      expect((await http.post(Uri.parse('$base/api/t/orders'), body: jsonEncode({'table': 'T1'}))).statusCode, 400, reason: 'customer is required');
      final spec = jsonDecode((await http.get(Uri.parse('$base/api/_spec'))).body) as Map;
      expect((spec['tables'] as List).firstWhere((t) => t['id'] == 'orders')['fields'].map((f) => f['id']), isNot(contains('status')));
    });

    test('pause shows a paused page and stops tools', () async {
      server.paused = true;
      expect((await http.get(Uri.parse('$base/'))).statusCode, 503);
      final s = McpSession(HttpTransport('$base/mcp'));
      await s.initialize();
      final r = await s.callTool('list_menu_items', {});
      expect(r.isError, isTrue);
      expect(r.text, contains('paused'));
    });

    test('MCP: customers order by name; manager tools need the PIN', () async {
      final pub = McpSession(HttpTransport('$base/mcp'));
      await pub.initialize();
      final tools = await pub.listTools();
      expect(tools.map((t) => t.name), containsAll(['list_menu_items', 'add_orders', 'get_hours', 'list_tables']));
      expect(tools.map((t) => t.name), isNot(contains('update_menu_items')));
      final addOrder = tools.firstWhere((t) => t.name == 'add_orders');
      expect(addOrder.autoApprove, isTrue);
      expect(addOrder.readOnly, isFalse);
      expect(tools.firstWhere((t) => t.name == 'list_menu_items').readOnly, isTrue);

      final r = await pub.callTool('add_orders', {'customer': 'Bob', 'table': 't1', 'items': [{'item': 'Carbonara', 'qty': 1}]});
      expect(r.isError, isFalse, reason: r.text);
      expect(r.text, contains('1 × Carbonara'));
      expect((await pub.callTool('get_hours', {})).text, contains('12:00'));

      final bad = McpSession(HttpTransport('$base/mcp/manager'));
      await expectLater(bad.initialize(), throwsA(isA<McpNeedsAuth>()));

      final mgr = McpSession(HttpTransport('$base/mcp/manager', headers: {'X-Key': '123456'}));
      await mgr.initialize();
      final mt = (await mgr.listTools()).map((t) => t.name).toSet();
      expect(mt, containsAll(['list_orders', 'update_orders', 'add_menu_items', 'set_hours', 'delete_menu_items']));
      expect(mt.intersection(tools.map((t) => t.name).toSet()), isEmpty, reason: 'no tool is offered twice to the owner');
      final orderId = int.parse(RegExp(r'id (\d+)').firstMatch(r.text)!.group(1)!);
      final up = await mgr.callTool('update_orders', {'id': orderId, 'status': 'cooking'});
      expect(up.text, contains('Status: Cooking'));
      expect((await mgr.callTool('list_orders', {})).text, contains('Bob'));
    });
  });

  test('builder asks again when the JSON is wrong, then repairs it', () async {
    final replies = ['oops', '{"fields": []}', '{"fields":[{"id":"Dish Name","type":"string"},{"id":"cost","type":"price"}]}'];
    var calls = 0;
    final b = AppBuilder((msgs, {json = false, model}) async {
      expect(json, isTrue);
      return replies[calls++];
    });
    final spec = AppSpec.fromJson({'name': 'x', 'tables': [{'id': 'menu', 'access': 'see'}]});
    final fields = await b.tableFields(spec, 'menu', const []);
    expect(calls, 3);
    expect(fields.map((f) => '${f.id}:${f.type}'), ['dish_name:text', 'cost:money']);
    // Still wrong after three tries: a clear error.
    final never = AppBuilder((msgs, {json = false, model}) async => 'nope');
    await expectLater(never.tableFields(spec, 'menu', const []), throwsA(isA<BuildError>()));
  });

  test('ChatMessage images go to Ollama', () {
    final m = ChatMessage('user', 'hi', images: ['iVBOR']);
    expect(ChatMessage.mimeOf(m.images.first), 'image/png');
    expect(ChatMessage.mimeOf('/9j/4AAQ'), 'image/jpeg');
  });

  test('template uses the business name; delete removes everything', () async {
    final tmp = Directory.systemTemp.createTempSync('tpl_del');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final forgotten = <String>[];
    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {}, forgetServer: (n) async => forgotten.add(n));
    final t = AppTemplate('x', 'Restaurant', 'test', {...restaurant, 'name': 'Sample Diner', 'site': {'tagline': 'Welcome to Sample Diner', 'phone': '000'}}, {
      'menu_items': [{'name': 'Soup', 'price': 5}],
    });
    final id = await apps.createFromTemplate(t, name: 'Luigi’s Place', phone: '0123 456');
    final a = (await apps.app(id))!;
    expect(a.name, 'Luigi’s Place');
    expect(a.spec.site['tagline'], 'Welcome to Luigi’s Place');
    expect(a.spec.site['phone'], '0123 456');
    expect(await AppData(db, id, a.spec).count('menu_items'), 1);
    expect((await http.get(Uri.parse('http://127.0.0.1:${a.port}/'))).statusCode, 200);
    File('${apps.filesDir(id)}/x.jpg')..createSync(recursive: true)..writeAsStringSync('x');
    expect((await db.all('mcp_servers')).length, 2);

    await apps.delete(id);
    expect(await apps.app(id), isNull);
    expect(await db.count('app_rows', where: 'app_id = ?', args: [id]), 0);
    expect(await db.count('mcp_servers'), 0);
    expect(Directory(apps.filesDir(id)).parent.existsSync(), isFalse);
    expect(forgotten, ['Luigi’s Place', 'Luigi’s Place (manager)']);
    await expectLater(http.get(Uri.parse('http://127.0.0.1:${a.port}/')), throwsA(anything), reason: 'the website is gone');
    await db.raw.close();
  });

  test('manager reads records from a photo; customers cannot', () async {
    final tmp = Directory.systemTemp.createTempSync('imp');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final spec = AppSpec.fromJson(restaurant);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('apps', {'name': 'x', 'request': 'x', 'spec': jsonEncode(spec.toJson()), 'port': 0, 'pin': '1234', 'created_at': now, 'updated_at': now});
    String? seenTable;
    final srv = AppServer(data: AppData(db, id, spec), pin: '1234', readPicture: (t, b64) async {
      seenTable = t;
      expect(base64Decode(b64), [1, 2, 3]);
      return [{'name': 'Lasagne', 'price': 11}];
    });
    await srv.start(0);
    final url = Uri.parse('http://127.0.0.1:${srv.port}/api/_import/menu_items');
    expect((await http.post(url, body: [1, 2, 3], headers: {'Content-Type': 'image/jpeg'})).statusCode, 403);
    final r = await http.post(url, body: [1, 2, 3], headers: {'Content-Type': 'image/jpeg', 'X-Key': '1234'});
    expect(r.statusCode, 200);
    expect(seenTable, 'menu_items');
    expect(jsonDecode(r.body)['rows'], [{'name': 'Lasagne', 'price': 11}]);
    await srv.stop();
  });
}
