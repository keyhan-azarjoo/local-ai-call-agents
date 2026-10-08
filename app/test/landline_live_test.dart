// ignore_for_file: avoid_print
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/state/app_state.dart';

/// A landline, end to end, with no real phone call: a simulated gateway box (SIPp) on this
/// computer's network address rings in like an FXO gateway would, with the line's login, speaks
/// a caller's words (G.711), and hangs up. Checks:
/// - the call is accepted only with the right login, and only from the gateway's address;
/// - the answer's audio address is this computer's local one (not the public one);
/// - the assistant answers: the call is saved with what it heard and said.
///
/// Needs the installed voice engine (uses the app's engine, models and phone service from its
/// data folder, with a temporary database), Ollama and `brew install sipp`. The caller's words are
/// test/landline/caller.wav (remake it with test/landline/make_caller_wav.py).
///   flutter test test/landline_live_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final real = '${Platform.environment['HOME']}/Library/Application Support/com.localailine.localailine';
  final tmp = Directory.systemTemp.createTempSync('landline');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);

  test('a landline gateway rings in, the assistant answers', () async {
    if (!File('/opt/homebrew/bin/sipp').existsSync() || !Directory('$real/engine').existsSync() || !File('test/landline/caller.wav').existsSync()) {
      return markTestSkipped('needs sipp, the installed voice engine and /tmp/landline');
    }
    // The installed engine, models and phone service; a fresh database.
    for (final d in ['engine', 'models', 'bin']) {
      Link('${tmp.path}/$d').createSync('$real/$d');
    }
    final s = AppState(dbPath: '${tmp.path}/s.db');
    addTearDown(() async => s.voice?.stop()); // the engine stops whatever happens
    await s.init();
    await s.startHost(port: 47421); // a fixed port: the voice engine is told where to reach the app
    final u = await s.auth.createUser(name: 'Sam Owner', username: 'owner', password: 'password-123', role: Role.owner);
    await s.completeSetup(u);
    await s.setLlmModel('qwen3:4b-instruct');
    await s.refreshEngine();

    final lan = (await Process.run('ipconfig', ['getifaddr', 'en0'])).stdout.toString().trim();
    expect(lan, isNotEmpty, reason: 'needs a network address');
    final lineId = await s.db.insert('lines', {
      'provider': 'fxo',
      'label': 'Landline (FXO box)',
      'number': '01632 960123',
      'config': jsonEncode({'host': lan, 'number': '01632 960123'}),
      'status': 'saved',
    });
    final said = await s.setInbound(lineId, true);
    print('Answer calls here: $said');
    expect(said, startsWith('Ready'), reason: said);
    final cfg = (jsonDecode('${(await s.db.all('lines', where: 'id = ?', args: [lineId])).first['config']}') as Map).cast<String, dynamic>();

    Future<ProcessResult> ring({required String from, required String pass, String scenario = 'test/landline/gateway_call.xml', int timeout = 60}) => Process.run('/opt/homebrew/bin/sipp', [
          '$lan:5080', '-sf', scenario, '-s', '01632960123', '-i', from, '-p', '5099', '-mi', from, '-mp', '6000',
          '-au', '${cfg['sipUser']}', '-ap', pass, '-m', '1', '-trace_msg', '-message_file', '${tmp.path}/sip-$pass.log', '-timeout', '${timeout}s', '-nostdin',
        ]);

    // The wrong password: refused.
    final bad = await ring(from: lan, pass: 'wrong-password', timeout: 15);
    print('wrong password: exit ${bad.exitCode}');
    expect(bad.exitCode, isNot(0), reason: 'a wrong login must not get through');

    // From another address (this computer's loopback, not the gateway): refused.
    final other = await Process.run('/opt/homebrew/bin/sipp', [
      '127.0.0.1:5080', '-sf', 'test/landline/gateway_call.xml', '-s', '01632960123', '-i', '127.0.0.1', '-p', '5098',
      '-au', '${cfg['sipUser']}', '-ap', '${cfg['sipPass']}', '-m', '1', '-timeout', '15s', '-nostdin',
    ]);
    print('other address: exit ${other.exitCode}');
    expect(other.exitCode, isNot(0), reason: 'only the gateway may ring in');

    // The gateway, with its login: answered.
    final ok = await ring(from: lan, pass: '${cfg['sipPass']}');
    final log = File('${tmp.path}/sip-${cfg['sipPass']}.log').readAsStringSync();
    print('gateway call: exit ${ok.exitCode}\n${ok.stdout.toString().split('\n').where((l) => l.contains('Successful') || l.contains('Failed')).join('\n')}');
    expect(ok.exitCode, 0, reason: 'the call should be answered and end normally\n${ok.stdout}');
    final answer = RegExp(r'SIP/2.0 200 OK[\s\S]*?c=IN IP4 ([0-9.]+)').firstMatch(log)?.group(1);
    print('answer audio address: $answer (this computer: $lan)');
    expect(answer, lan, reason: 'audio must come to the local address, not the public one');

    // The assistant took the call: saved with what it heard and what it said.
    Map<String, Object?>? call;
    for (var i = 0; i < 240 && call == null; i++) { // (a summary is written first: up to 2 minutes)
      await Future.delayed(const Duration(milliseconds: 500));
      call = (await s.db.all('calls', where: 'direction = ?', args: ['incoming'], orderBy: 'id DESC')).firstOrNull;
    }
    print('call saved: ${call?['summary']}\n${call?['transcript']}');
    expect(call, isNotNull, reason: 'the call should be saved');
    expect('${call!['transcript']}', isNotEmpty);
    await s.voice?.stop();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
