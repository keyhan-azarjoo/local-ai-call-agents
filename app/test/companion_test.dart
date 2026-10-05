import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/companion/host_client.dart';
import 'package:localailine/services/companion/host_server.dart';

void main() {
  late Db db;
  late Directory tmp;
  late HostServer host;
  late String base;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ll_comp');
    db = await Db.open(path: '${tmp.path}/h.db');
    host = HostServer(db, hostName: 'Mac mini', handlers: {
      'status': (_, _) async => {'answering': true, 'agent': 'Ava'},
      'echo': (id, b) async => {'device': id, 'got': b['x']},
    });
    await host.start(port: 0, discovery: false);
    base = 'http://127.0.0.1:${host.port}';
  });
  tearDown(() async {
    await host.stop();
    await db.raw.close();
    await tmp.delete(recursive: true);
  });

  test('hello identifies the computer', () async {
    expect(await HostClient.hello(base), 'Mac mini');
    expect(HostClient.normalize('192.168.1.20'), 'http://192.168.1.20:7420');
    expect(HostClient.normalize('mini.local:9000'), 'http://mini.local:9000');
  });

  test('pairing: wrong code refused, right code works once, then API works', () async {
    final code = host.newPairingCode();
    expect(() => HostClient.pair(base, '000000', 'iPhone', 'ios'), throwsA(isA<HostError>()));
    final p = await HostClient.pair(base, code, 'iPhone', 'ios');
    expect(p.hostName, 'Mac mini');
    expect(await db.count('devices'), 1);
    // The token itself is never stored, only its hash.
    expect((await db.all('devices')).first['token_hash'], isNot(p.token));
    // Same code can't pair a second device.
    expect(() => HostClient.pair(base, code, 'Other', 'android'), throwsA(isA<HostError>()));

    final c = HostClient(base, p.token);
    expect((await c.get('status'))['agent'], 'Ava');
    expect((await c.post('echo', {'x': 5}))['got'], 5);
  });

  test('unpaired or removed device is refused', () async {
    final c = HostClient(base, 'not-a-real-token');
    expect(() => c.get('status'), throwsA(isA<HostError>().having((e) => e.unpaired, 'unpaired', isTrue)));
    final p = await HostClient.pair(base, host.newPairingCode(), 'iPhone', 'ios');
    await db.delete('devices', (await db.all('devices')).first['id'] as int);
    expect(() => HostClient(base, p.token).get('status'), throwsA(isA<HostError>()));
  });

  test('five wrong codes lock pairing until a new code is shown', () async {
    final code = host.newPairingCode();
    for (var i = 0; i < 5; i++) {
      await expectLater(HostClient.pair(base, '111111', 'x', 'ios'), throwsA(isA<HostError>()));
    }
    await expectLater(HostClient.pair(base, code, 'x', 'ios'), throwsA(isA<HostError>()));
    final again = host.newPairingCode();
    expect((await HostClient.pair(base, again, 'x', 'ios')).hostName, 'Mac mini');
  });

  test('ring reaches the phone; the phone answers; approvals round-trip', () async {
    final p = await HostClient.pair(base, host.newPairingCode(), 'iPhone', 'ios');
    final phone = HostClient(base, p.token);
    phone.onApprove = (r) async => r['tool'] == 'safe_tool';
    final rang = Completer<Map<String, dynamic>>();
    phone.events.listen((e) {
      if (e['type'] == 'ring' && !rang.isCompleted) rang.complete(e);
    });
    await phone.connect();
    for (var i = 0; i < 20 && host.live.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(host.live.length, 1);

    final answer = host.ring(callId: 'c1', from: 'Sarah', number: '+44 7700 900123', line: 'Twilio', timeout: const Duration(seconds: 5));
    final e = await rang.future.timeout(const Duration(seconds: 3));
    expect(e['from'], 'Sarah');
    phone.answer('c1', 'me');
    final a = await answer;
    expect(a.action, 'me');
    expect(a.deviceName, 'iPhone');

    final id = host.live.keys.first;
    expect(await host.approveOn(id, 'Weighing', 'safe_tool', {}), isTrue);
    expect(await host.approveOn(id, 'Weighing', 'delete_all', {}), isFalse);

    // Ring with nobody answering: Ava takes it.
    final none = await host.ring(callId: 'c2', from: 'X', number: '1', line: 'L', timeout: const Duration(milliseconds: 300));
    expect(none.action, 'ai');
    await phone.close();
  });

  test('a device with ring off is not rung', () async {
    final p = await HostClient.pair(base, host.newPairingCode(), 'iPhone', 'ios');
    await db.update('devices', (await db.all('devices')).first['id'] as int, {'ring': 0});
    final phone = HostClient(base, p.token);
    var rang = false;
    phone.events.listen((e) => rang = rang || e['type'] == 'ring');
    await phone.connect();
    await Future.delayed(const Duration(milliseconds: 200));
    final a = await host.ring(callId: 'c3', from: 'X', number: '1', line: 'L', timeout: const Duration(milliseconds: 300));
    expect(a.action, 'ai');
    expect(rang, isFalse);
    await phone.close();
  });
}
