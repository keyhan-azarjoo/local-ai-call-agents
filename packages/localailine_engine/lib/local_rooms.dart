import 'package:localailine_core/services/voice_engine.dart';
import 'package:localailine_model/api.dart';

/// Live calls on this computer's own voice server.
class LocalRooms implements CallRoomsApi {
  LocalRooms(this._voice);
  final VoiceEngine? Function() _voice;

  VoiceEngine get _v => _voice() ?? (throw StateError(notReady!));

  @override
  String? get notReady {
    final v = _voice();
    if (v == null) return 'Calls are joined on the main computer.';
    if (!v.ready) return 'Live voice isn’t running (Settings → Voice & hearing).';
    return null;
  }

  @override
  String get url => _v.livekitUrl;

  @override
  Future<String> joinToken({required String identity, required String room, String? name, bool canPublish = true, bool hidden = false, bool canUpdateOwnMetadata = false}) =>
      _v.token(identity: identity, room: room, name: name, canPublish: canPublish, canPublishData: canPublish, hidden: hidden, canUpdateOwnMetadata: canUpdateOwnMetadata);

  @override
  Future<bool> roomExists(String room) => _v.roomExists(room);

  @override
  Future<void> endCall(String room) async => _voice()?.deleteRoom(room);

  @override
  Future<void> sendAgent(String room, {String metadata = ''}) => _v.dispatchAgent(room, metadata: metadata);
}
