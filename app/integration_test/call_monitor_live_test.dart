// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:localailine_core/services/voice_engine.dart';
import 'package:localailine/state/app_state.dart' show LocalRooms;
import 'package:localailine_ui/state/call_monitor.dart';

/// The Calls page's Listen / Take over / Hand back / Speak as the caller, with the app's own
/// LiveKit client, on a live voice test call (no real phone call). Needs LocalAILine running with
/// live voice on (its engine answers the call):
///   flutter test integration_test/call_monitor_live_test.dart -d macos
/// (This replaces the debug .app: rebuild it afterwards.)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final home = Platform.environment['HOME']!;
  final data = '$home/Library/Application Support/com.localailine.localailine';

  test('listen, take over, hand back and speak as the caller on a live call', () async {
    final v = VoiceEngine(dataDir: data, appUrl: '', appKey: '');
    const port = 8939;
    final caller = await Process.start('${v.engineDir}/.venv/bin/python', [
      'assets/engine/voice_caller.py', '--persona-file', 'assets/engine/voice_personas.json', '--persona', 'en_restaurant_booking',
      '--control-port', '$port', '--max-seconds', '150', '--quiet',
    ]);
    caller.stdout.drain<void>();
    caller.stderr.transform(utf8.decoder).listen((l) => l.contains('Error') ? print(l) : null);
    addTearDown(caller.kill);

    // The test call's room.
    String? room;
    for (var i = 0; i < 60 && room == null; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final rooms = (await v.roomApi('RoomService', 'ListRooms', {}))['rooms'] as List? ?? [];
      room = rooms.map((r) => '${(r as Map)['name']}').where((n) => n.contains('_vt$port-')).firstOrNull;
    }
    expect(room, isNotNull, reason: 'the test caller should ring in');
    expect(CallMonitor.callerPort(room!), port);
    bool agentIn(Room r) => r.remoteParticipants.values.any((p) => p.kind == ParticipantKind.AGENT);

    // Listen: a hidden listener hears the call.
    final listener = Room();
    await listener.connect(v.livekitUrl, await CallMonitor.tokenFor(LocalRooms(() => v), room, takeover: false, name: 'Keyhan'));
    var loud = 0.0;
    for (var i = 0; i < 100 && loud < .01; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      for (final p in listener.remoteParticipants.values) {
        if (p.audioLevel > loud) loud = p.audioLevel;
      }
    }
    print('listening: loudest ${loud.toStringAsFixed(3)}; tracks ${listener.remoteParticipants.values.expand((p) => p.audioTrackPublications).where((t) => t.subscribed).length}');
    expect(loud, greaterThan(.01), reason: 'the listener should hear the call');
    for (var i = 0; i < 40 && !agentIn(listener); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(agentIn(listener), isTrue);

    // Take over: as CallMonitor._tellAgent does.
    final owner = Room();
    await owner.connect(v.livekitUrl, await CallMonitor.tokenFor(LocalRooms(() => v), room, takeover: true, name: 'Keyhan'));
    await owner.localParticipant!.setAttributes({CallMonitor.takeoverAttribute: 'Keyhan'});
    await owner.localParticipant!.publishData(CallMonitor.takeoverMessage('Keyhan'), reliable: true, topic: CallMonitor.topic);
    final t0 = DateTime.now();
    while (agentIn(owner) && DateTime.now().difference(t0).inSeconds < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    print('the AI left after ${DateTime.now().difference(t0).inMilliseconds} ms');
    expect(agentIn(owner), isFalse, reason: 'the AI should leave the call to the owner');
    expect(owner.remoteParticipants.values.any((p) => p.identity.startsWith('sip_')), isTrue, reason: 'the caller stays');

    // Hand back: clear the attribute, send the AI back in.
    await owner.localParticipant!.setAttributes({CallMonitor.takeoverAttribute: ''});
    await v.dispatchAgent(room, metadata: jsonEncode({'handback': true, 'by': 'Keyhan'}));
    for (var i = 0; i < 50 && !agentIn(owner); i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await owner.disconnect();
    await Future.delayed(const Duration(seconds: 4));
    expect(agentIn(listener), isTrue, reason: 'the AI should be back on the call and stay');

    // Speak as the caller, then hand the caller's side back.
    final took = await CallMonitor.callerControl(room, 'takeover', by: 'Keyhan', client: http.Client());
    print('speak as the caller: $took');
    await Future.delayed(const Duration(seconds: 2));
    final back = await CallMonitor.callerControl(room, 'handback', client: http.Client());
    print('hand back to the test caller: $back');
    await listener.disconnect();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
