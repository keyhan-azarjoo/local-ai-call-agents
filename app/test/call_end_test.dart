import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/state/app_state.dart';

void main() {
  const booked = 'Your table for four is booked for Friday at seven.';
  const anything = 'You’re welcome! Is there anything else I can help you with?';

  test('a plain thank you is not the end: they are asked if there is anything else', () {
    for (final s in ['Thank you', 'Thanks a lot', 'Great, thanks', 'Perfect', 'Cheers', 'Lovely, thank you', 'Gracias', 'Merci beaucoup', 'ممنون']) {
      expect(AppState.callerDone(s, asked: booked), isFalse, reason: s);
      expect(AppState.thanksOnly(s), isTrue, reason: s);
    }
  });

  test('"no, thank you" after "anything else?" ends the call', () {
    for (final s in ['No, thank you', 'No thanks', 'Nope, I’m good', 'No', 'Thanks', 'That’s fine, thanks', 'No, gracias', 'Nein danke', 'نه ممنون']) {
      expect(AppState.callerDone(s, asked: anything), isTrue, reason: s);
    }
  });

  test('"no" without being asked if there is anything else is not the end', () {
    expect(AppState.callerDone('No thanks', asked: 'Would you like a starter with that?'), isFalse);
    expect(AppState.callerDone('No', asked: booked), isFalse);
  });

  test('a goodbye or "that is all" ends it any time', () {
    for (final s in ['Thanks, bye!', 'That’s all, thank you', 'Nothing else, cheers', 'Goodbye', 'Have a good day', 'Adiós', 'خداحافظ']) {
      expect(AppState.callerDone(s, asked: booked), isTrue, reason: s);
    }
  });

  test('more to ask is never the end', () {
    for (final s in ['Thanks — and can I also order a cake?', 'Yes, actually, what time do you close?', 'No, but I want to change the time', 'Thanks, could I book another for Saturday']) {
      expect(AppState.callerDone(s, asked: anything), isFalse, reason: s);
      expect(AppState.thanksOnly(s), isFalse, reason: s);
    }
  });

  test('a yes to a question is not a thank-you', () {
    expect(AppState.thanksOnly('Yes please, thanks'), isFalse);
    expect(AppState.thanksOnly('Sure, sounds good'), isFalse);
  });

  test('knows when it asked if there is anything else', () {
    expect(AppState.askedAnythingElse(anything), isTrue);
    expect(AppState.askedAnythingElse('Can I help with anything else today?'), isTrue);
    expect(AppState.askedAnythingElse('¿Hay algo más en lo que pueda ayudarle?'), isTrue);
    expect(AppState.askedAnythingElse(booked), isFalse);
  });

  test('asking for a teammate by name, even misheard', () {
    const team = ['Mia', 'Rex', 'Jay', 'Leon', 'Kim'];
    for (final s in ['Could I speak to Mia, please?', 'Can I speak to me a', 'Sure, I\'d like to talk to Mayor please', 'speak to? Me out.', 'I\'m asking for Rex']) {
      expect(AppState.askedForTeammate(s, team), isNotNull, reason: s);
    }
    expect(AppState.askedForTeammate('Can I speak to Mia', team), 'Mia');
    expect(AppState.askedForTeammate('Can I speak to the manager?', team), isNull);
    expect(AppState.askedForTeammate('Could I talk to Mark please', team), isNull);
    expect(AppState.askedForTeammate('I want a fade with Jay on Friday', team), isNull);
    expect(AppState.askedForTeammate('Can I speak to someone about a refund', team), isNull);
  });

  test('their number is the one they are calling from', () {
    for (final s in ["My name is Hugo and I'm calling from this phone number.", 'Use the number I\'m calling from', 'same number', 'you can use the number you see', "I'm ringing from my mobile"]) {
      expect(AppState.ownNumber(s), isTrue, reason: s);
    }
    expect(AppState.ownNumber('My number is 07700 900123'), isFalse);
  });

  test('a tool written out instead of called is never said aloud', () {
    const t = 'I\'ll take a message. Can I have your name? [take_message:{"name":"Greta","phone":"+441174960708","message":"call back"}]';
    expect(AppState.spokenText(t), 'I\'ll take a message. Can I have your name?');
    // While it is still coming in, the start of it is held back.
    expect(AppState.spokenText('Sure. [take_message:{"name":"Gre'), 'Sure.');
    // The engine's own tags stay (they are removed later, by the voice engine).
    expect(AppState.spokenText('Passing you over. [voice:af_bella|Mia] Hi'), contains('[voice:af_bella|Mia]'));
  });
}
