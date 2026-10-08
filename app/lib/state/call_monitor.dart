import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import '../services/voice_engine.dart';
import 'app_state.dart';

/// What this computer is doing on a live call.
enum MonitorMode { off, connecting, listening, takenOver, handingBack }

class _Session {
  _Session(this.room, this.mode);
  final String room;
  MonitorMode mode;
  Room? lk;
  EventsListener<RoomEvent>? events;
  Timer? tick;
  double level = 0;
  bool muted = false;
  String speaking = ''; // caller | agent | owner | ''
}

/// The owner on a live call, from the Calls page (one call at a time):
///  - Listen: joins the call's LiveKit room as a hidden listener that can't speak, and plays the
///    caller and the AI through this computer's speakers. Leaving changes nothing for the call.
///  - Take over: joins with this computer's microphone and tells the AI to step out (a data
///    message on topic 'localailine', and an attribute); the caller stays on with the owner.
///    Then "Hand back to AI" sends the voice agent back in, or "End call" hangs up.
///  - Voice test calls (rooms with `_vt`): the test caller script's control server makes the owner
///    the caller (their microphone instead of the simulated customer), and hands back.
/// None of this places a phone call.
class CallMonitor extends ChangeNotifier {
  CallMonitor(this.app);
  final AppState app;
  _Session? _s;

  /// Voice test calls being switched between the owner and the simulated caller.
  final _callerBusy = <String>{};

  static const topic = 'localailine';
  static const takeoverAttribute = 'localailine.takeover';
  static const defaultCallerPort = 8925;

  MonitorMode modeOf(String room) => _s?.room == room ? _s!.mode : MonitorMode.off;
  double levelOf(String room) => _s?.room == room ? _s!.level : 0;
  bool mutedOn(String room) => _s?.room == room && _s!.muted;

  /// Who is speaking on the call being listened to: 'caller', 'agent', 'owner' or ''.
  String speakingOn(String room) => _s?.room == room ? _s!.speaking : '';
  bool callerBusy(String room) => _callerBusy.contains(room);

  /// A call from the voice test caller (it can hand the caller's side to the owner).
  static bool isVoiceTest(String room) => room.contains('_vt');

  /// The test caller's control port: in the room name (`…_vt8926…`), else 8925.
  static int callerPort(String room) {
    final p = int.tryParse(RegExp(r'_vt[-_:]?(\d{4,5})(?!\d)').firstMatch(room)?.group(1) ?? '');
    return p != null && p >= 1024 && p <= 65535 ? p : defaultCallerPort;
  }

  /// The token to join a call: a hidden listener that can't publish anything, or the owner taking
  /// over (microphone, the message to the AI, and the takeover attribute).
  static Future<String> tokenFor(VoiceEngine v, String room, {required bool takeover, required String name, String? id}) {
    id ??= Random().nextInt(1 << 32).toRadixString(36);
    return takeover
        ? v.token(identity: 'owner-$id', room: room, name: name, canPublish: true, canPublishData: true, canUpdateOwnMetadata: true)
        : v.token(identity: 'listen-$id', room: room, name: '$name (listening)', canPublish: false, canPublishData: false, hidden: true);
  }

  /// What the voice agent receives to step out (see takeover_by in localailine_voice.py).
  static List<int> takeoverMessage(String by) => utf8.encode(jsonEncode({'takeover': true, 'by': by}));

  @visibleForTesting
  void debugSet(String room, MonitorMode mode, {double level = 0, String speaking = '', bool muted = false}) {
    _s = mode == MonitorMode.off
        ? null
        : (_Session(room, mode)
            ..level = level
            ..speaking = speaking
            ..muted = muted);
    notifyListeners();
  }

  /// Listen in: the call's audio on this computer's speakers.
  Future<void> listen(String room) => _join(room, takeover: false);

  /// Take over from the AI: this computer's microphone joins the call and the AI leaves it.
  Future<void> takeOver(String room) => _join(room, takeover: true);

  /// Stop listening (the call goes on as it was).
  Future<void> stop(String room) async {
    final s = _s;
    if (s == null || s.room != room || s.mode == MonitorMode.takenOver) return;
    _s = null;
    notifyListeners();
    await _close(s);
  }

  String? _notReady() {
    final v = app.voice;
    if (v == null) return 'Calls are joined on the main computer.';
    if (!v.ready) return 'Live voice isn’t running (Settings → Voice & hearing).';
    return null;
  }

  Future<void> _join(String room, {required bool takeover}) async {
    final why = _notReady();
    if (why != null) return app.toast(why);
    final v = app.voice!;
    final old = _s;
    if (old != null) {
      if (old.mode == MonitorMode.takenOver && old.room != room) return app.toast('You’re on another call: hand it back or end it first.');
      if (old.mode == MonitorMode.takenOver || old.mode == MonitorMode.handingBack) return;
      _s = null;
      await _close(old); // (listening to this call: rejoined with the microphone)
    }
    final s = _s = _Session(room, MonitorMode.connecting);
    notifyListeners();
    try {
      if (!await v.roomExists(room)) throw StateError('this call has no live audio (a text-only test call, or it has just ended)');
      final r = Room(
        roomOptions: const RoomOptions(
          defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, noiseSuppression: true, autoGainControl: true),
        ),
      );
      s.lk = r;
      s.events = r.createListener()
        ..on<RoomDisconnectedEvent>((_) => unawaited(_gone(s)))
        ..on<ParticipantDisconnectedEvent>((_) {
          // On a call the owner took over, the caller hanging up ends it.
          if (s.mode == MonitorMode.takenOver && !r.remoteParticipants.values.any((p) => p.kind != ParticipantKind.AGENT)) unawaited(_callerHungUp(s));
        });
      await r.connect(v.livekitUrl, await tokenFor(v, room, takeover: takeover, name: app.ownerName));
      if (_s != s) return _close(s); // stopped while connecting
      if (takeover) {
        await r.localParticipant?.setMicrophoneEnabled(true);
        app.liveTakeover(room, app.ownerName);
        await _tellAgent(r);
        // In case the AI missed it (it was just joining, say): once more.
        Timer(const Duration(seconds: 3), () {
          if (_s == s && s.mode == MonitorMode.takenOver && r.remoteParticipants.values.any((p) => p.kind == ParticipantKind.AGENT)) unawaited(_tellAgent(r));
        });
      }
      s.mode = takeover ? MonitorMode.takenOver : MonitorMode.listening;
      s.tick = Timer.periodic(const Duration(milliseconds: 150), (_) => _measure(s));
      notifyListeners();
    } catch (e) {
      if (_s == s) _s = null;
      notifyListeners();
      await _close(s);
      app.toast(takeover ? 'Couldn’t take over the call: $e' : 'Couldn’t listen in: $e');
    }
  }

  Future<void> _tellAgent(Room r) async {
    final me = r.localParticipant;
    if (me == null) return;
    try {
      await me.setAttributes({takeoverAttribute: app.ownerName});
    } catch (_) {}
    await me.publishData(takeoverMessage(app.ownerName), reliable: true, topic: topic);
  }

  /// Mute or unmute this computer's microphone on a call the owner took over.
  Future<void> toggleMute(String room) async {
    final s = _s;
    if (s == null || s.room != room || s.mode != MonitorMode.takenOver) return;
    s.muted = !s.muted;
    notifyListeners();
    await s.lk?.localParticipant?.setMicrophoneEnabled(!s.muted);
  }

  /// The AI comes back to a call the owner took over; the owner leaves once it has joined.
  Future<void> handBack(String room) async {
    final s = _s;
    if (s == null || s.room != room || s.mode != MonitorMode.takenOver) return;
    final v = app.voice;
    final r = s.lk;
    if (v == null || r == null) return;
    s.mode = MonitorMode.handingBack;
    notifyListeners();
    try {
      // (The returning AI would otherwise see the owner still taking over, and leave again.)
      try {
        await r.localParticipant?.setAttributes({takeoverAttribute: ''});
      } catch (_) {}
      await v.dispatchAgent(room, metadata: jsonEncode({'handback': true, 'by': app.ownerName}));
      for (var i = 0; i < 50 && _s == s && !r.remoteParticipants.values.any((p) => p.kind == ParticipantKind.AGENT); i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (_s != s) return;
      if (!r.remoteParticipants.values.any((p) => p.kind == ParticipantKind.AGENT)) throw StateError('the AI didn’t join');
      app.liveHandedBack(room);
      _s = null;
      notifyListeners();
      await _close(s);
    } catch (e) {
      if (_s == s) {
        s.mode = MonitorMode.takenOver;
        try {
          await r.localParticipant?.setAttributes({takeoverAttribute: app.ownerName});
        } catch (_) {}
        notifyListeners();
      }
      app.toast('Couldn’t hand the call back to the AI ($e). You’re still on the call.');
    }
  }

  /// Hang up a call the owner took over.
  Future<void> endCall(String room) async {
    final s = _s;
    if (s == null || s.room != room) return;
    _s = null;
    notifyListeners();
    await _close(s);
    app.liveCallGone(room);
    try {
      await app.voice?.deleteRoom(room);
    } catch (_) {}
  }

  Future<void> _callerHungUp(_Session s) async {
    if (_s != s) return;
    _s = null;
    notifyListeners();
    await _close(s);
    app.liveCallGone(s.room);
    try {
      await app.voice?.deleteRoom(s.room); // (nobody is left in it)
    } catch (_) {}
  }

  /// The room closed (the call ended).
  Future<void> _gone(_Session s) async {
    if (_s != s) return;
    final wasOn = s.mode == MonitorMode.takenOver || s.mode == MonitorMode.handingBack;
    _s = null;
    notifyListeners();
    await _close(s);
    if (wasOn) app.liveCallGone(s.room);
  }

  void _measure(_Session s) {
    final r = s.lk;
    if (r == null || _s != s) return;
    final remote = r.remoteParticipants.values;
    final me = r.localParticipant;
    final on = s.mode == MonitorMode.takenOver;
    var level = 0.0;
    for (final p in remote) {
      level = max(level, p.audioLevel);
    }
    if (on && me != null && !s.muted) level = max(level, me.audioLevel);
    final caller = remote.any((p) => p.kind != ParticipantKind.AGENT && p.isSpeaking);
    final agent = remote.any((p) => p.kind == ParticipantKind.AGENT && p.isSpeaking);
    final owner = on && !s.muted && (me?.isSpeaking ?? false);
    final who = caller ? 'caller' : (owner ? 'owner' : (agent ? 'agent' : ''));
    if (on) app.liveOnCall(s.room, owner: owner, caller: caller);
    if ((level - s.level).abs() > .03 || who != s.speaking) {
      s
        ..level = level
        ..speaking = who;
      notifyListeners();
    }
  }

  Future<void> _close(_Session s) async {
    s.tick?.cancel();
    s.tick = null;
    await s.events?.dispose();
    s.events = null;
    final r = s.lk;
    s.lk = null;
    if (r != null) {
      try {
        await r.disconnect();
      } catch (_) {}
      await r.dispose();
    }
  }

  // ---------- voice test calls: the owner as the caller ----------

  /// The test caller's control server (see assets/engine/voice_caller.py): [what] is 'takeover'
  /// (the owner's microphone becomes the caller), 'handback' (the simulated caller resumes) or 'state'.
  static Future<Map<String, dynamic>> callerControl(String room, String what, {String by = '', http.Client? client}) async {
    final port = callerPort(room);
    final c = client ?? http.Client();
    try {
      final uri = Uri.parse('http://127.0.0.1:$port/$what');
      final r = await (what == 'state'
              ? c.get(uri)
              : c.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'room': room, if (by.isNotEmpty) 'by': by})))
          .timeout(const Duration(seconds: 5));
      Map<String, dynamic> j;
      try {
        j = r.body.trim().isEmpty ? {} : (jsonDecode(r.body) as Map).cast<String, dynamic>();
      } catch (_) {
        j = {'text': r.body};
      }
      if (r.statusCode != 200 || j['ok'] == false) {
        throw StateError('the voice test caller said: ${j['error'] ?? j['msg'] ?? j['text'] ?? 'error ${r.statusCode}'}');
      }
      return j;
    } on SocketException {
      throw StateError('the voice test caller isn’t running (nothing answers on 127.0.0.1:$port)');
    } on TimeoutException {
      throw StateError('the voice test caller didn’t answer on 127.0.0.1:$port');
    } on http.ClientException {
      throw StateError('the voice test caller isn’t running (nothing answers on 127.0.0.1:$port)');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Speak as the caller on a voice test call (or [back] to the simulated caller).
  Future<void> speakAsCaller(String room, {bool back = false, http.Client? client}) async {
    if (_callerBusy.contains(room)) return;
    _callerBusy.add(room);
    notifyListeners();
    try {
      await callerControl(room, back ? 'handback' : 'takeover', by: app.ownerName, client: client);
      app.liveCallerAs(room, back ? null : app.ownerName);
    } catch (e) {
      app.toast(back ? 'Couldn’t hand back to the test caller: $e' : 'Couldn’t speak as the caller: $e');
    } finally {
      _callerBusy.remove(room);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final s = _s;
    _s = null;
    if (s != null) unawaited(_close(s));
    super.dispose();
  }
}
