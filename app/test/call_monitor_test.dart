import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/voice_engine.dart';
import 'package:localailine/state/call_monitor.dart';

/// Listening in on a call, taking it over, and speaking as the caller on voice test calls:
/// the tokens, the message to the AI, and the test caller's control server.
void main() {
  late Directory dir;
  late VoiceEngine v;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('ll_monitor');
    v = VoiceEngine(dataDir: dir.path, appUrl: 'http://127.0.0.1:7420', appKey: 'k');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> claims(String jwt) =>
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1])))) as Map<String, dynamic>;

  const room = 'pstn-in-1-_+447700900123_abc';

  test('listening: a hidden participant that can only hear', () async {
    final c = claims(await CallMonitor.tokenFor(v, room, takeover: false, name: 'Keyhan', id: 'x1'));
    expect(c['sub'], 'listen-x1');
    final video = c['video'] as Map;
    expect(video['room'], room);
    expect(video['roomJoin'], true);
    expect(video['canSubscribe'], true);
    expect(video['canPublish'], false);
    expect(video['canPublishData'], false);
    expect(video['hidden'], true);
    expect(video['roomAdmin'], false);
    expect(video['roomCreate'], false);
    expect(video.containsKey('canUpdateOwnMetadata'), false);
    expect(c.containsKey('sip'), false);
  });

  test('taking over: the microphone, the message to the AI, and its own attribute', () async {
    final c = claims(await CallMonitor.tokenFor(v, room, takeover: true, name: 'Keyhan', id: 'x2'));
    expect(c['sub'], 'owner-x2'); // the voice agent only steps out for "owner-…"
    expect(c['name'], 'Keyhan');
    final video = c['video'] as Map;
    expect(video['room'], room);
    expect(video['canPublish'], true);
    expect(video['canPublishData'], true);
    expect(video['canSubscribe'], true);
    expect(video['canUpdateOwnMetadata'], true);
    expect(video.containsKey('hidden'), false);
    expect(video['roomAdmin'], false); // can't end or change anything else
    expect(c.containsKey('sip'), false); // and can't place a call
  });

  test('ordinary tokens are as before; admin ones can list rooms', () async {
    final plain = claims(await v.token(identity: 'you-1', room: 'talk-caller-auto-1'))['video'] as Map;
    expect(plain['canPublish'], true);
    expect(plain['canPublishData'], true);
    expect(plain.containsKey('hidden'), false);
    expect(plain.containsKey('roomList'), false);
    final admin = claims(await v.token(identity: 'localailine-app', room: room, sipAdmin: true))['video'] as Map;
    expect(admin['roomList'], true);
    expect(admin['roomAdmin'], true);
  });

  test('the message that tells the AI to step out', () {
    expect(jsonDecode(utf8.decode(CallMonitor.takeoverMessage('Keyhan'))), {'takeover': true, 'by': 'Keyhan'});
    expect(CallMonitor.topic, 'localailine');
    expect(CallMonitor.takeoverAttribute, 'localailine.takeover');
  });

  test('voice test calls and their control port', () {
    expect(CallMonitor.isVoiceTest('pstn-in-0-_+447700900999_vt1712345678'), true);
    expect(CallMonitor.isVoiceTest(room), false);
    expect(CallMonitor.callerPort('pstn-in-0-_+447700900999_vt'), 8925);
    expect(CallMonitor.callerPort('pstn-in-0-_+447700900999_vt1712345678'), 8925); // a time, not a port
    expect(CallMonitor.callerPort('pstn-in-0-_+447700900999_vt8931'), 8931);
    expect(CallMonitor.callerPort('pstn-in-0-_+447700900999_vt-8931_x'), 8931);
    expect(CallMonitor.callerPort('pstn-in-0-_+447700900999_vt0099'), 8925);
  });

  test('the test caller control server: takeover, handback, state', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final got = <String>[];
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      got.add('${req.method} ${req.uri.path} $body');
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/state') {
        req.response.write(jsonEncode({'ok': true, 'owner': got.length > 1}));
      } else if (req.uri.path == '/broken') {
        req.response.statusCode = 500;
        req.response.write(jsonEncode({'error': 'no microphone'}));
      } else {
        req.response.write(jsonEncode({'ok': true}));
      }
      await req.response.close();
    });
    final vt = 'pstn-in-0-_+447700900999_vt${server.port}';
    expect(CallMonitor.callerPort(vt), server.port);
    await CallMonitor.callerControl(vt, 'takeover', by: 'Keyhan');
    expect(got.last, startsWith('POST /takeover '));
    expect(jsonDecode(got.last.substring('POST /takeover '.length)), {'room': vt, 'by': 'Keyhan'});
    expect((await CallMonitor.callerControl(vt, 'state'))['owner'], true);
    await CallMonitor.callerControl(vt, 'handback');
    expect(got.last, startsWith('POST /handback '));
    await expectLater(CallMonitor.callerControl(vt, 'broken'), throwsA(predicate((e) => '$e'.contains('no microphone'))));
  });

  test('a clear error when the test caller is not running', () async {
    // A free port: bound, then closed.
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    await expectLater(
      CallMonitor.callerControl('pstn-in-0-_+447700900999_vt$port', 'takeover'),
      throwsA(predicate((e) => '$e'.contains('isn’t running') && '$e'.contains('127.0.0.1:$port'))),
    );
  });
}
