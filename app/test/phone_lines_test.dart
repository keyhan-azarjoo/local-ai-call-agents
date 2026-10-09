import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/state/app_state.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_core/services/phone.dart';
import 'package:localailine_core/services/sip_gateway.dart';
import 'package:localailine_core/services/voice_engine.dart';
import 'package:localailine_model/phone_lines.dart';
import 'package:path/path.dart' as p;

/// Your own number through your provider (the phone gateway), and who takes the calls on a line.
/// Nothing here places a call or reaches a provider: the gateway and LiveKit are fakes.
void main() {
  group('who takes calls (a line\'s answer mode)', () {
    test('a line saved before modes existed: the AI answers, as before', () {
      final a = LineAnswer.of({'number': '+447700900123'});
      expect(a.mode, AnswerMode.ai);
      expect(a.ringSeconds, 20);
      expect(a.plan(), isNull); // (the voice worker is told nothing new)
    });

    test('modes and ring time round-trip through the line config', () {
      for (final m in AnswerMode.values) {
        final cfg = LineAnswer(m, ringSeconds: 35).applyTo({'number': '+1'});
        final back = LineAnswer.of(jsonDecode(jsonEncode(cfg)) as Map<String, dynamic>);
        expect(back.mode, m);
        expect(back.ringSeconds, 35);
      }
      expect(LineAnswer.of({'answerMode': 'nonsense'}).mode, AnswerMode.ai);
      expect(LineAnswer.of({'answerMode': 'ring', 'ringSeconds': '2'}).ringSeconds, LineAnswer.minRingSeconds);
      expect(LineAnswer.of({'answerMode': 'ring', 'ringSeconds': 900}).ringSeconds, LineAnswer.maxRingSeconds);
    });

    test('what the voice worker is told', () {
      expect(const LineAnswer(AnswerMode.off).plan(), {'off': true});
      expect(const LineAnswer(AnswerMode.ring, ringSeconds: 25).plan(), {'wait': 25, 'then': 'message'});
      expect(const LineAnswer(AnswerMode.ringThenAi, ringSeconds: 15).plan(), {'wait': 15, 'then': 'ai'});
    });

    test('ring time typed in the page', () {
      expect(LineAnswer.ringSecondsProblem('20'), isNull);
      expect(LineAnswer.ringSecondsProblem('soon'), contains('number of seconds'));
      expect(LineAnswer.ringSecondsProblem('3'), contains('between'));
      expect(LineAnswer.ringSecondsProblem('500'), contains('between'));
    });
  });

  group('my number, through my provider (line settings)', () {
    const good = SipLine(number: '+447700900123', domain: 'sip.example.com', username: '1234567e0', password: 'secret');

    test('a complete line is fine, and goes to the gateway as its account', () {
      expect(good.problem(), isNull);
      final a = good.toGatewayAccount(on: true);
      expect(a, {'number': '+447700900123', 'domain': 'sip.example.com', 'port': 5061, 'transport': 'tls', 'username': '1234567e0', 'password': 'secret', 'mode': 'on'});
      expect(good.toGatewayAccount(on: false)['mode'], 'off');
      expect(SipLine.gatewayId(12), 'line12');
    });

    test('ports: given, else 5061 for TLS and 5060 otherwise', () {
      expect(SipLine.of({'transport': 'tcp'}).effectivePort, 5060);
      expect(SipLine.of({'transport': 'udp'}).effectivePort, 5060);
      expect(SipLine.of({}).effectivePort, 5061);
      expect(SipLine.of({'port': '5080'}).effectivePort, 5080);
      expect(SipLine.of({'transport': 'carrier pigeon'}).transport, 'tls');
    });

    test('each problem in plain words', () {
      SipLine l({String number = '+447700900123', String domain = 'sip.example.com', int? port, String user = 'u1', String auth = '', String pass = 'p', String proxy = ''}) =>
          SipLine(number: number, domain: domain, port: port, username: user, authUsername: auth, password: pass, outboundProxy: proxy);
      expect(l(number: '').problem(), 'Add your phone number.');
      expect(l(number: '07700900123').problem(), contains('country code'));
      expect(l(domain: '').problem(), contains('SIP server'));
      expect(l(domain: 'sip:example.com:5060').problem(), contains('without “sip:” or a port'));
      expect(l(port: 70000).problem(), contains('port'));
      expect(l(user: '').problem(), contains('username'));
      expect(l(user: 'has space').problem(), contains('characters'));
      expect(l(auth: 'bad user').problem(), contains('authentication username'));
      expect(l(pass: '').problem(), 'Add the SIP password.');
      expect(l(pass: '').problem(needPassword: false), isNull); // (editing: keeps the saved one)
      expect(l(proxy: 'proxy.example.com:99999').problem(), contains('outbound proxy'));
      expect(l(proxy: 'proxy.example.com:5060').problem(), isNull);
    });

    test('lines saved before this type could connect are read too', () {
      final old = SipLine.of({'server': 'sip.old.example', 'sipUser': 'alice', 'sipPass': 'pw', 'number': '+15550100100'});
      expect((old.domain, old.username, old.password, old.preset), ('sip.old.example', 'alice', 'pw', 'generic'));
    });

    test('an empty password on an edit keeps the gateway\'s', () {
      const edit = SipLine(number: '+447700900123', domain: 'sip.example.com', username: 'u', password: '');
      expect(edit.toGatewayAccount(on: true).containsKey('password'), isFalse);
    });

    test('presets fill in the usual settings, and every one says to check', () {
      expect(sipPresets.first.id, 'generic');
      for (final pr in sipPresets) {
        expect(SipLine.transports, contains(pr.transport));
        expect(pr.note, isNotEmpty, reason: pr.id);
      }
      expect(sipPresets.firstWhere((x) => x.id == 'telnyx').domain, 'sip.telnyx.com');
    });

    test('numbers with their country code', () {
      expect(normalizePhoneNumber('+44 7700 900123'), '+447700900123');
      expect(normalizePhoneNumber('0044 7700 900123'), '+447700900123');
      expect(normalizePhoneNumber('07700 900123'), '07700900123');
    });

    test('sign-in states in words', () {
      expect(SipLineStatus.fromGateway({'status': {'state': 'registered'}}).words, contains('Connected'));
      final failed = SipLineStatus.fromGateway({'status': {'state': 'failed', 'last_error': 'wrong username or password'}});
      expect(failed.words, 'Couldn’t sign in: wrong username or password');
      expect(const SipLineStatus('off').words, contains('other phones'));
    });
  });

  group('the phone gateway\'s control API', () {
    late FakeGateway gw;
    late SipGatewayClient client;
    setUp(() async {
      gw = await FakeGateway.start();
      client = SipGatewayClient(gw.base, FakeGateway.token);
    });
    tearDown(() async {
      client.close();
      await gw.close();
    });

    test('adds a line, reads its state, lists and removes it', () async {
      const line = SipLine(number: '+447700900123', domain: 'sip.example.com', username: 'u1', password: 'pw');
      final v = await client.put('line3', line.toGatewayAccount(on: true));
      expect(v['status']['state'], 'registered');
      expect(v.containsKey('password'), isFalse);
      expect(gw.accounts['line3']!['password'], 'pw');
      expect((await client.get('line3'))!['number'], '+447700900123');
      expect([for (final a in await client.list()) a['id']], ['line3']);
      expect(await client.delete('line3'), isTrue);
      expect(await client.get('line3'), isNull);
      expect(await client.delete('line3'), isFalse);
      expect(await client.healthy(), isTrue);
    });

    test('the gateway\'s own words when a line is refused', () async {
      await expectLater(client.put('line1', const {'number': '0770', 'domain': 'x', 'username': 'u', 'password': 'p'}),
          throwsA(isA<SipGatewayError>().having((e) => e.message, 'message', contains('international format'))));
    });

    test('a wrong token is refused', () async {
      final wrong = SipGatewayClient(gw.base, 'not-the-token-at-all');
      await expectLater(wrong.list(), throwsA(isA<SipGatewayError>().having((e) => e.status, 'status', 401)));
      wrong.close();
    });

    test('trying a line: added signed out, tested once, then removed', () async {
      gw.testResult = (false, 'wrong username or password (the provider said 403 Forbidden)');
      const line = SipLine(number: '+447700900123', domain: 'sip.example.com', username: 'u1', password: 'bad');
      final r = await client.tryLine(line, tempId: 'test-1');
      expect(r.ok, isFalse);
      expect(r.result, contains('wrong username or password'));
      expect(gw.log, ['PUT test-1 off', 'POST test-1/test', 'DELETE test-1']);
      expect(gw.accounts, isEmpty);
      gw.testResult = (true, 'registered');
      expect((await client.tryLine(line, tempId: 'test-2')).ok, isTrue);
    });
  });

  group('LiveKit\'s side of your own number', () {
    late Directory dir;
    late FakeLiveKit lk;
    late Phone phone;
    late VoiceEngine v;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ll_sipgw');
      lk = await FakeLiveKit.start();
      v = VoiceEngine(dataDir: dir.path, appUrl: 'http://127.0.0.1:1', appKey: 'k');
      phone = Phone(v)..livekitHttp = lk.base;
    });
    tearDown(() async {
      await lk.close();
      dir.deleteSync(recursive: true);
    });

    test('calls from the gateway: only from this computer, with its login, into the line\'s rooms', () async {
      await phone.ensureGatewayLine({'number': '+447700900123'}, lineId: 7);
      expect(lk.calls.map((c) => c.$1), ['CreateSIPInboundTrunk', 'CreateSIPDispatchRule']);
      final trunk = lk.calls[0].$2['trunk'] as Map;
      expect(trunk['numbers'], ['+447700900123']);
      expect(trunk['allowed_addresses'], ['127.0.0.1/32']);
      expect(trunk['auth_username'], v.gatewaySecrets['livekitUser']);
      expect(trunk['auth_password'], v.gatewaySecrets['livekitPass']);
      expect((trunk['headers_to_attributes'] as Map)['X-LL-Line'], 'll.line');
      final rule = lk.calls[1].$2;
      expect(((rule['rule'] as Map)['dispatch_rule_individual'] as Map)['room_prefix'], 'pstn-in-7-');
      expect(rule['trunk_ids'], ['trunk-1']);
      // Once per LiveKit run; again after LiveKit restarts.
      await phone.ensureGatewayLine({'number': '+447700900123'}, lineId: 7);
      expect(lk.calls, hasLength(2));
      phone.forgetLiveKit();
      await phone.ensureGatewayLine({'number': '+447700900123'}, lineId: 7);
      expect(lk.calls, hasLength(4));
    });

    test('calls out go through the gateway with the line\'s number', () async {
      for (final part in [EnginePart.livekit, EnginePart.whisper, EnginePart.agent, EnginePart.sip]) {
        v.state[part] = PartState.running;
      }
      await phone.call(line: {'provider': 'sip', 'number': '+447700900123', 'lineId': 7}, number: '+447700900999', room: 'pstn-out-3');
      expect(lk.calls.map((c) => c.$1), ['CreateSIPOutboundTrunk', 'CreateSIPParticipant']);
      final trunk = lk.calls[0].$2['trunk'] as Map;
      expect(trunk['address'], '127.0.0.1:${VoiceEngine.gatewayInternalPort}');
      expect(trunk['transport'], 'SIP_TRANSPORT_TCP');
      expect(trunk['numbers'], ['+447700900123']);
      expect(trunk['auth_username'], v.gatewaySecrets['outboundUser']);
      expect((trunk['headers'] as Map)['X-LL-Line'], 'line7');
      expect(lk.calls[1].$2['sip_trunk_id'], 'trunk-1');
      expect(lk.calls[1].$2['sip_call_to'], '+447700900999');
    });

    test('the gateway\'s logins are made once, kept private, and not shared with the Twilio bridge', () {
      final s = v.gatewaySecrets;
      expect(s['outboundPass']!.length, greaterThanOrEqualTo(12)); // (the gateway asks for 12+)
      expect(base64.decode(s['storeKey']!), hasLength(32));
      expect(VoiceEngine(dataDir: dir.path, appUrl: '', appKey: '').gatewaySecrets, s);
      final mode = File(p.join(dir.path, 'sipgw.secret')).statSync().modeString();
      expect(mode, 'rw-------');
      expect(VoiceEngine.gatewayInternalPort, isNot(5090)); // the Twilio call bridge's port
    });
  });

  group('the gateway\'s source is carried by the app, not copied', () {
    final pkg = Directory(p.join('..', 'packages', 'localailine_sipgw'));

    test('every source file is listed, in the app and in the package\'s asset list', () {
      final real = [
        'go.mod',
        'go.sum',
        for (final f in pkg.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.go') && !f.path.endsWith('_test.go')) p.relative(f.path, from: pkg.path),
      ]..sort();
      expect([...sipGatewaySources]..sort(), real);
      final pubspec = File(p.join(pkg.path, 'pubspec.yaml')).readAsStringSync();
      final listed = [for (final m in RegExp(r'^    - (\S+)$', multiLine: true).allMatches(pubspec)) m.group(1)!]..sort();
      expect(listed, real);
    });

    test('a source change means a rebuild', () async {
      final dir = Directory.systemTemp.createTempSync('ll_sipgw_hash');
      addTearDown(() => dir.deleteSync(recursive: true));
      final v = VoiceEngine(dataDir: dir.path, appUrl: '', appKey: '');
      final h1 = await VoiceEngine.sourceHash({'a.go': 'package a', 'go.mod': 'module x'});
      expect(await VoiceEngine.sourceHash({'go.mod': 'module x', 'a.go': 'package a'}), h1);
      expect(await VoiceEngine.sourceHash({'a.go': 'package b', 'go.mod': 'module x'}), isNot(h1));
      expect(v.gatewayOutdated(h1), isTrue); // (never built here)
    });
  });

  group('the engine: who takes each call', () {
    late Directory dir;
    late AppEngine e;
    late HttpServer srv;
    late int sipLine, aiLine, offLine, twilioLine;

    Future<Map<String, dynamic>> ask(String path, Map<String, String> q) async {
      final r = await http.get(Uri.parse('http://127.0.0.1:${srv.port}$path').replace(queryParameters: q));
      return (jsonDecode(r.body) as Map).cast<String, dynamic>();
    }

    Future<int> line(String provider, Map<String, dynamic> cfg) =>
        e.db.insert('lines', {'provider': provider, 'label': 'Line', 'number': cfg['number'], 'config': jsonEncode(cfg), 'status': 'saved'});

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ll_answer');
      final path = p.join(dir.path, 'localailine.db');
      // (No init: nothing here starts or reaches Ollama, LiveKit or a provider.)
      e = AppEngine(dbPath: path);
      e.db = await Db.open(path: path);
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) => e.engineRequest(r, r.uri.path));
      const sip = {'number': '+447700900100', 'domain': 'sip.example.com', 'username': 'u', 'password': 'p'};
      sipLine = await line('sip', const LineAnswer(AnswerMode.ringThenAi, ringSeconds: 20).applyTo(sip));
      aiLine = await line('sip', {...sip, 'number': '+447700900101'});
      offLine = await line('sip', const LineAnswer(AnswerMode.off).applyTo({...sip, 'number': '+447700900102'}));
      twilioLine = await line('twilio', const LineAnswer(AnswerMode.ring, ringSeconds: 5).applyTo({'number': '+447700900103', 'inbound': true}));
    });

    tearDown(() async {
      await srv.close(force: true);
      await e.db.raw.close();
      dir.deleteSync(recursive: true);
    });

    test('"AI answers": voice-config is exactly as before (no answer plan)', () async {
      final cfg = await ask('/api/voice-config', {'room': 'pstn-in-$aiLine-_+447700900555_abc', 'mode': 'caller'});
      expect(cfg.containsKey('answer'), isFalse);
      expect(cfg['greeting'], isNotEmpty);
    });

    test('"Off": the worker is told not to answer', () async {
      final cfg = await ask('/api/voice-config', {'room': 'pstn-in-$offLine-_+447700900555_abc', 'mode': 'caller'});
      expect(cfg['answer'], {'off': true});
    });

    test('ring me, then the AI: rings, and "Let the AI answer" releases it at once', () async {
      final room = 'pstn-in-$sipLine-_+447700900555_abc';
      final cfg = await ask('/api/voice-config', {'room': room, 'mode': 'caller'});
      expect(cfg['answer'], {'wait': 20, 'then': 'ai'});
      expect(e.ringing.keys, [room]);
      expect(e.liveCalls[room]?.agent, 'ringing');
      final waiting = ask('/api/call-answer', {'room': room});
      await Future.delayed(const Duration(milliseconds: 100));
      final at = DateTime.now();
      e.releaseCall(room);
      expect(await waiting, {'go': 'ai'});
      expect(DateTime.now().difference(at), lessThan(const Duration(seconds: 2)));
      expect(e.ringing, isEmpty);
      expect(e.liveCalls[room]?.agent, 'listening');
    });

    test('a call is decided once: handed back to the AI later, it isn\'t rung again', () async {
      final room = 'pstn-in-$sipLine-_+447700900555_once';
      expect((await ask('/api/voice-config', {'room': room, 'mode': 'caller'}))['answer'], isNotNull);
      e.releaseCall(room);
      expect((await ask('/api/voice-config', {'room': room, 'mode': 'caller'})).containsKey('answer'), isFalse);
    });

    test('test calls (line 0) and other rooms are never rung', () async {
      expect(await e.answerPlan('pstn-in-0-_+447700900555_t'), isNull);
      expect(await e.answerPlan('talk-caller-en-1'), isNull);
      expect(await e.answerPlan('pstn-out-4'), isNull);
    });

    test('answered on this computer (take over while ringing): the worker leaves it to the owner', () async {
      final room = 'pstn-in-$sipLine-_+447700900555_own';
      await ask('/api/voice-config', {'room': room, 'mode': 'caller'});
      final waiting = ask('/api/call-answer', {'room': room});
      await Future.delayed(const Duration(milliseconds: 100));
      e.liveTakeover(room, 'Keyhan');
      expect(await waiting, {'go': 'owner', 'by': 'Keyhan'});
      expect(e.ringing, isEmpty);
    });

    test('ring me: nobody answers in the ring time, so the AI takes a message', () async {
      final room = 'pstn-in-$twilioLine-_+447700900555_msg';
      final cfg = await ask('/api/voice-config', {'room': room, 'mode': 'caller'});
      expect(cfg['answer'], {'wait': 5, 'then': 'message'});
      final at = DateTime.now();
      final r = await ask('/api/call-answer', {'room': room});
      expect(r['go'], 'message');
      expect(r['greeting'], contains('take a message'));
      expect(DateTime.now().difference(at).inMilliseconds, inInclusiveRange(4000, 7000));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('the caller hangs up while ringing: a missed call, and the ringing stops', () async {
      final room = 'pstn-in-$sipLine-_+447700900555_gone';
      await ask('/api/voice-config', {'room': room, 'mode': 'caller'});
      await http.post(Uri.parse('http://127.0.0.1:${srv.port}/api/call-ended'),
          body: jsonEncode({
            'room': room,
            'transcript': [{'role': 'note', 'text': 'Missed: hung up while it was ringing'}],
            'answered': false,
            'outcome': 'Missed: hung up while it was ringing',
          }));
      for (var i = 0; i < 40 && await e.db.count('calls') == 0; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(e.ringing, isEmpty);
      final call = (await e.db.all('calls', orderBy: 'id')).single;
      expect(call['outcome'], 'Missed: hung up while it was ringing');
      expect(call['number'], '+447700900555');
      // (A late question from the worker gets the AI, never a hang.)
      expect(await ask('/api/call-answer', {'room': room}), {'go': 'ai'});
    });

    test('changing who takes calls is saved on the line', () async {
      final r = await e.setLineAnswer(aiLine, AnswerMode.ring, ringSeconds: 30);
      expect(r, contains('30 seconds'));
      final cfg = jsonDecode('${(await e.db.all('lines', where: 'id = ?', args: [aiLine])).single['config']}') as Map<String, dynamic>;
      expect(LineAnswer.of(cfg).mode, AnswerMode.ring);
      expect(LineAnswer.of(cfg).ringSeconds, 30);
      expect(cfg['password'], 'p'); // (the rest of the line is kept)
    });
  });
}

/// A stand-in for the phone gateway's control API (packages/localailine_sipgw/internal/api).
class FakeGateway {
  FakeGateway._(this._s);
  final HttpServer _s;
  static const token = 'fake-control-token-0123456789';
  final accounts = <String, Map<String, dynamic>>{};
  final log = <String>[];
  (bool, String) testResult = (true, 'registered');
  String get base => 'http://127.0.0.1:${_s.port}';

  static Future<FakeGateway> start() async {
    final g = FakeGateway._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    g._s.listen(g._handle);
    return g;
  }

  Future<void> close() => _s.close(force: true);

  Map<String, dynamic> _view(String id) => {
        ...Map.of(accounts[id]!)..remove('password'),
        'id': id,
        'has_password': true,
        'status': {'state': accounts[id]!['mode'] == 'off' ? 'off' : 'registered'},
      };

  Future<void> _handle(HttpRequest r) async {
    Future<void> send(int code, [Object? body]) async {
      r.response.statusCode = code;
      if (body != null) {
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(body));
      }
      await r.response.close();
    }

    final path = r.uri.path;
    if (path == '/healthz') return send(200, {'status': 'ok'});
    if (r.headers.value('authorization') != 'Bearer $token') return send(401, {'error': 'missing or wrong bearer token'});
    final m = RegExp(r'^/v1/accounts(?:/([^/]+))?(/test)?$').firstMatch(path);
    if (m == null) return send(404, {'error': 'not found'});
    final id = m.group(1);
    switch ((r.method, id, m.group(2))) {
      case ('GET', null, _):
        return send(200, {'accounts': [for (final k in accounts.keys) _view(k)]});
      case ('GET', final String id, null):
        return accounts.containsKey(id) ? send(200, _view(id)) : send(404, {'error': 'no such account'});
      case ('PUT', final String id, null):
        final a = (jsonDecode(await utf8.decodeStream(r)) as Map).cast<String, dynamic>();
        if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch('${a['number']}')) return send(400, {'error': 'number must be in international format, e.g. +447700900123'});
        accounts[id] = {...?accounts[id], ...a};
        log.add('PUT $id ${a['mode']}');
        return send(200, _view(id));
      case ('DELETE', final String id, null):
        log.add('DELETE $id');
        return accounts.remove(id) == null ? send(404, {'error': 'no such account'}) : send(204);
      case ('POST', final String id, '/test'):
        log.add('POST $id/test');
        return send(200, {'ok': testResult.$1, 'result': testResult.$2});
    }
    return send(405, {'error': 'method not allowed'});
  }
}

/// A stand-in for LiveKit's SIP API (Twirp, JSON): records each request, answers with ids.
class FakeLiveKit {
  FakeLiveKit._(this._s);
  final HttpServer _s;
  final calls = <(String, Map<String, dynamic>)>[];
  var _n = 0;
  String get base => 'http://127.0.0.1:${_s.port}';

  static Future<FakeLiveKit> start() async {
    final f = FakeLiveKit._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    f._s.listen((r) async {
      final method = r.uri.pathSegments.last;
      f.calls.add((method, (jsonDecode(await utf8.decodeStream(r)) as Map).cast<String, dynamic>()));
      final body = switch (method) {
        'CreateSIPInboundTrunk' || 'CreateSIPOutboundTrunk' => {'sip_trunk_id': 'trunk-${++f._n}'},
        'CreateSIPDispatchRule' => {'sip_dispatch_rule_id': 'rule-1'},
        _ => {'participant_id': 'p-1'},
      };
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(body));
      await r.response.close();
    });
    return f;
  }

  Future<void> close() => _s.close(force: true);
}
