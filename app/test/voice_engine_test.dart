import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/phone.dart';
import 'package:localailine/services/voice_engine.dart';
import 'package:localailine/state/app_state.dart';

void main() {
  test('LiveKit token is a valid HS256 JWT for one room', () async {
    final dir = Directory.systemTemp.createTempSync('ll_voice');
    addTearDown(() => dir.deleteSync(recursive: true));
    final v = VoiceEngine(dataDir: dir.path, appUrl: 'http://127.0.0.1:7420', appKey: 'k');
    final jwt = await v.token(identity: 'you-1', room: 'talk-caller-auto-1', name: 'Sam');
    final parts = jwt.split('.');
    expect(parts, hasLength(3));
    final mac = await Hmac.sha256().calculateMac(utf8.encode('${parts[0]}.${parts[1]}'), secretKey: SecretKey(utf8.encode(v.apiSecret)));
    final sig = base64Url.encode(mac.bytes).replaceAll('=', '');
    expect(parts[2], sig);
    final body = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
    expect(body['iss'], VoiceEngine.apiKey);
    expect(body['sub'], 'you-1');
    expect(body['video'], containsPair('room', 'talk-caller-auto-1'));
    expect(body['video'], containsPair('roomJoin', true));
    // The secret is private to this computer and survives restarts.
    expect(v.apiSecret.length, greaterThan(30));
    expect(VoiceEngine(dataDir: dir.path, appUrl: '', appKey: '').apiSecret, v.apiSecret);
  });

  test('streamed markdown becomes clean speech, never repeated', () {
    const reply = 'Our dishes without nuts are:  \n- **Tomato** soup\n- Halloumi fries\n\n1. Hummus\nThat’s all. CALL_TASK {"to":"x"}';
    var sent = '';
    final said = StringBuffer();
    for (var i = 1; i <= reply.length; i++) {
      final t = AppState.spokenText(reply.substring(0, i));
      if (t.length > sent.length) {
        said.write(t.substring(sent.length));
        sent = t;
      }
    }
    expect(said.toString().trim(), 'Our dishes without nuts are: Tomato soup. Halloumi fries. Hummus. That’s all.');
  });

  test('phone numbers in international form', () {
    expect(Phone.e164('07700 900124'), '07700 900124');
    expect(Phone.e164('07700 900124', lineNumber: '+441234988088'), '07700 900124');
    expect(Phone.e164('(415) 555-0100', lineNumber: '+16065432628'), '+14155550100');
    expect(Phone.e164('07700 900124'), '07700 900124');
  });
}
