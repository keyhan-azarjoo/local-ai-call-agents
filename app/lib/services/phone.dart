import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_engine.dart';

class PhoneError implements Exception {
  PhoneError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real phone calls: your Twilio number ↔ Twilio Elastic SIP trunk ↔ LiveKit SIP on this
/// computer ↔ Ava. Everything is set up with your own Twilio account; nothing else in between.
class Phone {
  Phone(this.engine, {http.Client? client}) : _c = client ?? http.Client();
  final VoiceEngine engine;
  final http.Client _c;

  /// LiveKit outbound trunk per line (LiveKit forgets them when it restarts).
  final _trunks = <String, String>{};

  // ---------------- Twilio ----------------

  static String _auth(Map<String, dynamic> cfg) {
    final user = '${cfg['keySid'] ?? ''}'.isNotEmpty ? cfg['keySid'] : cfg['sid'];
    return 'Basic ${base64Encode(utf8.encode('$user:${cfg['token']}'))}';
  }

  Future<Map<String, dynamic>> _twilio(Map<String, dynamic> cfg, String method, String url, [Map<String, String>? form]) async {
    final req = http.Request(method, Uri.parse(url))..headers['Authorization'] = _auth(cfg);
    if (form != null) req.bodyFields = form;
    final r = await http.Response.fromStream(await _c.send(req));
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) throw PhoneError('Twilio said ${r.statusCode}: ${body['message'] ?? r.body}');
    return body;
  }

  /// Makes sure the line has its own Twilio SIP trunk (named "LocalAILine") with a login only
  /// this computer knows. Your numbers and other trunks are left as they are.
  /// Returns the updated line settings (to save), or null when nothing changed.
  Future<Map<String, dynamic>?> ensureTwilioTrunk(Map<String, dynamic> cfg) async {
    if ('${cfg['sipDomain'] ?? ''}'.isNotEmpty && '${cfg['sipPass'] ?? ''}'.isNotEmpty) return null;
    final sid = cfg['sid'];
    final trunks = (await _twilio(cfg, 'GET', 'https://trunking.twilio.com/v1/Trunks'))['trunks'] as List;
    var trunk = trunks.cast<Map>().where((t) => t['friendly_name'] == 'LocalAILine').firstOrNull;
    final rnd = Random.secure();
    String hex(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    trunk ??= await _twilio(cfg, 'POST', 'https://trunking.twilio.com/v1/Trunks', {'FriendlyName': 'LocalAILine', 'DomainName': 'localailine-${hex(6)}.pstn.twilio.com'});
    final list = await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/$sid/SIP/CredentialLists.json', {'FriendlyName': 'LocalAILine ${hex(4)}'});
    // Twilio wants 12+ characters with upper and lower case letters and a digit.
    const abc = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final pass = 'Ll9${List.generate(24, (_) => abc[rnd.nextInt(abc.length)]).join()}';
    await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/$sid/SIP/CredentialLists/${list['sid']}/Credentials.json',
        {'Username': 'localailine', 'Password': pass});
    await _twilio(cfg, 'POST', 'https://trunking.twilio.com/v1/Trunks/${trunk['sid']}/CredentialLists', {'CredentialListSid': '${list['sid']}'});
    return {...cfg, 'sipDomain': trunk['domain_name'], 'trunkSid': trunk['sid'], 'sipUser': 'localailine', 'sipPass': pass, 'credentialListSid': list['sid']};
  }

  /// Sends calls to your number to this computer, with no router settings: this computer signs
  /// in to a private Twilio SIP address (the call bridge keeps that connection open) and the
  /// number rings it. The number's previous setup (e.g. another app) is saved to restore later.
  Future<Map<String, dynamic>> enableInbound(Map<String, dynamic> cfg) async {
    final sid = cfg['sid'];
    final nums = (await _twilio(cfg, 'GET', 'https://api.twilio.com/2010-04-01/Accounts/$sid/IncomingPhoneNumbers.json?PhoneNumber=${Uri.encodeQueryComponent('${cfg['number']}')}'))['incoming_phone_numbers'] as List;
    if (nums.isEmpty) throw PhoneError('${cfg['number']} isn’t a number in this Twilio account.');
    final n = nums.first as Map;
    final ownUrl = '${n['voice_url'] ?? ''}'.contains('twimlets.com/echo') && '${n['voice_url']}'.contains('localailine');
    final previous = cfg['previousVoice'] ?? (ownUrl ? null : {'url': n['voice_url'], 'method': n['voice_method'], 'trunk': n['trunk_sid']});

    // The private SIP address this computer signs in to.
    var domain = '${cfg['regDomain'] ?? ''}';
    if (domain.isEmpty) {
      final doms = ((await _twilio(cfg, 'GET', 'https://api.twilio.com/2010-04-01/Accounts/$sid/SIP/Domains.json'))['domains'] as List).cast<Map>();
      var d = doms.where((d) => d['friendly_name'] == 'LocalAILine').firstOrNull;
      final rnd = Random.secure();
      d ??= await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/$sid/SIP/Domains.json', {
        'DomainName': 'localailine-${List.generate(6, (_) => rnd.nextInt(16).toRadixString(16)).join()}.sip.twilio.com',
        'FriendlyName': 'LocalAILine',
        'SipRegistration': 'true',
        'VoiceUrl': 'https://twimlets.com/echo?Twiml=${Uri.encodeQueryComponent('<Response><Reject/></Response>')}',
        'VoiceMethod': 'GET',
      });
      for (final kind in ['Registrations', 'Calls']) {
        try {
          await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/$sid/SIP/Domains/${d['sid']}/Auth/$kind/CredentialListMappings.json',
              {'CredentialListSid': '${cfg['credentialListSid']}'});
        } on PhoneError catch (e) {
          if (!e.message.contains('already')) rethrow;
        }
      }
      domain = '${d['domain_name']}';
      cfg = {...cfg, 'regDomain': domain, 'regDomainSid': d['sid']};
    }
    // Off the trunk (if an earlier setup put it there), then ring our SIP address.
    if (n['trunk_sid'] != null && n['trunk_sid'] == cfg['trunkSid']) {
      await _twilio(cfg, 'DELETE', 'https://trunking.twilio.com/v1/Trunks/${cfg['trunkSid']}/PhoneNumbers/${n['sid']}');
    }
    final twiml = '<Response><Dial answerOnBridge="true" timeout="25"><Sip>sip:${cfg['sipUser']}@$domain;transport=tls</Sip></Dial></Response>';
    await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/$sid/IncomingPhoneNumbers/${n['sid']}.json',
        {'VoiceUrl': 'https://twimlets.com/echo?Twiml=${Uri.encodeQueryComponent(twiml)}', 'VoiceMethod': 'GET'});
    return {...cfg, 'inbound': true, 'previousVoice': ?previous, 'numberSid': n['sid']};
  }

  /// Gives the number back to its previous setup.
  Future<Map<String, dynamic>> disableInbound(Map<String, dynamic> cfg) async {
    final prev = (cfg['previousVoice'] as Map?) ?? {};
    if (cfg['numberSid'] != null) {
      await _twilio(cfg, 'POST', 'https://api.twilio.com/2010-04-01/Accounts/${cfg['sid']}/IncomingPhoneNumbers/${cfg['numberSid']}.json',
          {'VoiceUrl': '${prev['url'] ?? ''}', 'VoiceMethod': '${prev['method'] ?? 'POST'}'});
      if (prev['trunk'] != null) {
        await _twilio(cfg, 'POST', 'https://trunking.twilio.com/v1/Trunks/${prev['trunk']}/PhoneNumbers', {'PhoneNumberSid': '${cfg['numberSid']}'});
      }
    }
    return {...cfg, 'inbound': false};
  }

  /// What the call bridge needs to sign in.
  static Map<String, String> bridgeEnv(Map<String, dynamic> cfg) =>
      {'LL_REG_DOMAIN': '${cfg['regDomain']}', 'LL_REG_USER': '${cfg['sipUser']}', 'LL_REG_PASS': '${cfg['sipPass']}', 'LL_NUMBER': '${cfg['number']}'};

  /// Our public IP, asked from Twilio's STUN server (no other service involved).
  static Future<String?> publicIp() async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final done = Completer<String?>();
    sock.listen((e) {
      if (e != RawSocketEvent.read || done.isCompleted) return;
      final d = sock.receive();
      if (d == null) return;
      final b = ByteData.sublistView(d.data);
      for (var i = 20; i + 4 <= d.data.length;) {
        final t = b.getUint16(i), l = b.getUint16(i + 2);
        if (t == 0x0020 && l >= 8) {
          done.complete([for (var k = 0; k < 4; k++) d.data[i + 8 + k] ^ [0x21, 0x12, 0xa4, 0x42][k]].join('.'));
          return;
        }
        i += 4 + l + ((4 - l % 4) % 4);
      }
    });
    try {
      final host = (await InternetAddress.lookup('global.stun.twilio.com', type: InternetAddressType.IPv4)).first;
      final req = Uint8List(20);
      req.buffer.asByteData()
        ..setUint16(0, 1)
        ..setUint32(4, 0x2112A442);
      final rnd = Random.secure();
      for (var i = 8; i < 20; i++) {
        req[i] = rnd.nextInt(256);
      }
      for (var attempt = 0; attempt < 3 && !done.isCompleted; attempt++) {
        sock.send(req, host, 3478);
        await Future.any([done.future, Future.delayed(const Duration(seconds: 1))]);
      }
      return done.isCompleted ? await done.future : null;
    } catch (_) {
      return null;
    } finally {
      sock.close();
    }
  }

  /// The port calls come in on. Not 5060: home routers' "SIP ALG" interferes with that one.
  static const sipPort = 5080;

  // ---------------- LiveKit SIP ----------------

  Future<Map<String, dynamic>> _livekit(String method, Map<String, Object?> body) async {
    final jwt = await engine.token(identity: 'localailine-app', sipAdmin: true, ttl: const Duration(minutes: 5));
    final r = await _c.post(Uri.parse('http://127.0.0.1:${VoiceEngine.livekitPort}/twirp/livekit.SIP/$method'),
        headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'}, body: jsonEncode(body));
    final j = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw PhoneError(_reason('${j['msg'] ?? r.body}'));
    return j;
  }

  Future<String> _outboundTrunk(Map<String, dynamic> cfg) async {
    final landline = cfg['provider'] == 'fxo';
    final key = landline ? 'fxo|${cfg['host']}|${cfg['number']}' : '${cfg['sipDomain']}|${cfg['number']}';
    final known = _trunks[key];
    if (known != null) return known;
    if (landline) {
      // A landline: calls go out through the gateway on this network (it dials on the phone line).
      final j = await _livekit('CreateSIPOutboundTrunk', {
        'trunk': {
          'name': 'Landline ${cfg['number']}',
          'address': '${cfg['host']}${'${cfg['host']}'.contains(':') ? '' : ':5060'}',
          'numbers': [cfg['number']],
          if ('${cfg['gatewayUser'] ?? ''}'.isNotEmpty) 'auth_username': cfg['gatewayUser'],
          if ('${cfg['gatewayPass'] ?? ''}'.isNotEmpty) 'auth_password': cfg['gatewayPass'],
          'transport': 'SIP_TRANSPORT_UDP',
        },
      });
      return _trunks[key] = (j['sip_trunk_id'] ?? j['sipTrunkId']) as String;
    }
    final j = await _livekit('CreateSIPOutboundTrunk', {
      'trunk': {
        'name': 'Twilio ${cfg['number']}',
        'address': cfg['sipDomain'],
        'numbers': [cfg['number']],
        'auth_username': cfg['sipUser'],
        'auth_password': cfg['sipPass'],
        // Encrypted call setup: routers can't rewrite it (their SIP ALG breaks the audio).
        'transport': engine.sipTls ? 'SIP_TRANSPORT_TLS' : 'SIP_TRANSPORT_TCP',
      },
    });
    return _trunks[key] = (j['sip_trunk_id'] ?? j['sipTrunkId']) as String;
  }

  /// LiveKit side of incoming calls (it forgets them when it restarts): calls to the number
  /// get their own room "pstn-in-…", where Ava answers.
  final _inbound = <String>{};
  /// Calls to line [lineId] get rooms "pstn-in-(line id)-…", so the app knows which line (and so
  /// which agent answers).
  Future<void>? _inboundBusy;
  Future<void> ensureInbound(Map<String, dynamic> cfg, {int? lineId}) async {
    while (_inboundBusy != null) {
      await _inboundBusy;
    }
    final done = Completer<void>();
    _inboundBusy = done.future;
    try {
      await _ensureInbound(cfg, lineId: lineId);
    } on PhoneError catch (e) {
      // Already set up (e.g. by a start a moment ago): that's fine.
      if (!e.message.contains('Conflicting inbound')) rethrow;
      _inbound.add('${cfg['number']}');
    } finally {
      _inboundBusy = null;
      done.complete();
    }
  }

  Future<void> _ensureInbound(Map<String, dynamic> cfg, {int? lineId}) async {
    final number = '${cfg['number']}';
    if (_inbound.contains(number)) return;
    final t = await _livekit('CreateSIPInboundTrunk', {
      // Calls only from the call bridge on this computer: anything else on the network could ring
      // in pretending to be any number (and act on that person's bookings).
      'trunk': {'name': 'Twilio $number', 'numbers': [number], 'allowed_addresses': ['127.0.0.1/32']},
    });
    await _livekit('CreateSIPDispatchRule', {
      'rule': {
        'dispatch_rule_individual': {'room_prefix': lineId == null ? 'pstn-in-' : 'pstn-in-$lineId-'},
      },
      'trunk_ids': [t['sip_trunk_id'] ?? t['sipTrunkId']],
      'name': 'Answer $number',
    });
    _inbound.add(number);
  }

  /// A landline through a gateway box on this network (an "FXO" port, e.g. a Grandstream HT813):
  /// the landline plugs into the box, the box sends each call to this computer over the local
  /// network. Only that box may ring in (its address), and only with this line's login.
  Future<void> ensureLandline(Map<String, dynamic> cfg, {required int lineId}) async {
    final key = 'fxo:$lineId';
    if (_inbound.contains(key)) return;
    final host = '${cfg['host']}'.split(':').first.trim();
    if (InternetAddress.tryParse(host) == null) throw PhoneError('The gateway address should be its IP address on your network, e.g. 192.168.1.40.');
    final t = await _livekit('CreateSIPInboundTrunk', {
      'trunk': {
        'name': 'Landline ${cfg['number']}',
        'numbers': const <String>[], // whatever number the box sends: it's the landline
        'allowed_addresses': ['$host/32'],
        'auth_username': cfg['sipUser'],
        'auth_password': cfg['sipPass'],
      },
    });
    await _livekit('CreateSIPDispatchRule', {
      'rule': {
        'dispatch_rule_individual': {'room_prefix': 'pstn-in-$lineId-'},
      },
      'trunk_ids': [t['sip_trunk_id'] ?? t['sipTrunkId']],
      'name': 'Answer landline ${cfg['number']}',
    });
    _inbound.add(key);
  }

  /// What to set on the gateway box so calls come here.
  static List<(String, String)> gatewaySettings(Map<String, dynamic> cfg, String? lanIp) => [
        ('SIP server (primary)', '${lanIp ?? 'this computer’s IP address'}:$sipPort'),
        ('Transport', 'UDP'),
        ('SIP user ID and Authenticate ID', '${cfg['sipUser']}'),
        ('Authenticate password', '${cfg['sipPass']}'),
        ('Incoming calls from the phone line (PSTN → VoIP)', 'Forward every call to the SIP server, answering after one ring (often "Unconditional call forward to VoIP" or "Stage method: 1")'),
        ('Caller ID', 'Turn on caller ID detection, so the assistant knows who is calling'),
      ];

  /// Whether someone is in a call's room yet.
  Future<bool> inRoom(String room, String identity) async {
    final jwt = await engine.token(identity: 'localailine-app', room: room, sipAdmin: true, ttl: const Duration(minutes: 1));
    try {
      final r = await _c.post(Uri.parse('http://127.0.0.1:${VoiceEngine.livekitPort}/twirp/livekit.RoomService/ListParticipants'),
          headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'}, body: jsonEncode({'room': room}));
      return r.statusCode == 200 && r.body.contains(identity);
    } catch (_) {
      return false;
    }
  }

  /// Rings [number] from the line; Ava joins room [room] and takes over once they answer.
  /// Returns when the call is answered; throws with the reason if it isn't (busy, refused, no answer…).
  Future<void> call({required Map<String, dynamic> line, required String number, required String room, String? name}) async {
    if (!engine.phoneReady) throw PhoneError('Phone calling isn’t running. Start live voice (Settings → Voice) — phone calling must be installed.');
    final trunk = await _outboundTrunk(line);
    await _livekit('CreateSIPParticipant', {
      'sip_trunk_id': trunk,
      'sip_call_to': number,
      'room_name': room,
      'participant_identity': 'callee',
      'participant_name': name ?? number,
      'wait_until_answered': true,
    });
  }

  /// The call failed: say why in plain words.
  static String _reason(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('blacklist') || m.contains('32203')) return 'Your Twilio account blocked this number (calls to that country or number aren’t allowed — Twilio console → Voice → Geographic permissions).';
    if (m.contains('busy') || m.contains('486')) return 'The line was busy.';
    if (m.contains('no answer') || m.contains('480') || m.contains('408')) return 'No one answered.';
    if (m.contains('declin') || m.contains('603')) return 'They declined the call.';
    if (m.contains('404')) return 'That number doesn’t exist.';
    if (m.contains('401') || m.contains('403') || m.contains('auth')) return 'Twilio refused the call: $msg';
    return 'The call didn’t go through: $msg';
  }

  /// "+44 7700 900123", "07700 900123" (with a UK line) → "+447700900123".
  static String e164(String n, {String? lineNumber}) {
    final t = n.trim();
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.startsWith('+')) return '+$digits';
    if (t.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('0') && lineNumber != null) {
      // A national number: use the line's country code (+44, +1, …).
      final cc = RegExp(r'^\+(1|7|2\d|3\d|4\d|5\d|6\d|8\d|9\d)').firstMatch(lineNumber)?.group(1);
      if (cc != null) return '+$cc${digits.substring(1)}';
    }
    // A 10-digit North American number on a +1 line.
    if (lineNumber != null && lineNumber.startsWith('+1') && digits.length == 10) return '+1$digits';
    return '+$digits';
  }
}
