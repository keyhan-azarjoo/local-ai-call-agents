import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/ollama.dart';
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

  test('the model reads a hand-over back as only the new agent\'s words', () {
    expect(AppState.handedOver('I\'ll check that. ⏸ (on hold) Tessa: Hi, this is Tessa. Which booking?'), 'Hi, this is Tessa. Which booking?');
    expect(AppState.handedOver('Passing you over. [voice:af_bella|Mia] Hi, it\'s Mia.'), 'Hi, it\'s Mia.');
    expect(AppState.handedOver('Your table is booked for 7pm.'), 'Your table is booked for 7pm.');
  });

  test('a name said on its own after "what name is it under?" is their name', () {
    final convo = [
      ChatMessage('assistant', 'Could you tell me the name it is booked under?'),
      ChatMessage('user', 'Victoria Stone.'),
    ];
    expect(AppState.callerName(convo), 'Victoria Stone');
    expect(AppState.callerName([ChatMessage('assistant', 'What time?'), ChatMessage('user', 'Seven.')]), isNull);
    expect(AppState.callerName([ChatMessage('user', 'Hi, my name is Hugo Khan, cancel please')]), 'Hugo Khan');
  });

  test('a tool written as [name: key="value"] is not said either', () {
    expect(AppState.spokenText('Let me check. [check_appointments: date="2026-10-15", time="10:00"] It is free.'), 'Let me check. It is free.');
    expect(AppState.spokenText('Let me check. [check_appointments: date="2026'), 'Let me check.');
  });

  test('details written as data are said as people say them', () {
    // Heard on a voice test call: "Phone plus 447.700.900.258, date 2.026-10-09, time 20.30".
    final t = AppState.spokenText('Let me confirm that. [Name: Sam Carter, Phone: +447700900258, Date: 2026-10-09, Time: 20:30, Guests: 2, Table: 4 (Inside)]. Is that correct?');
    expect(t, 'Let me confirm that. name Sam Carter, phone 07700 900258, date Friday 9 October, time 8:30 pm, guests 2, table 4 (Inside). Is that correct?');
    expect(AppState.spokenText('Your table is at 7:30 pm on 2026-10-09.'), 'Your table is at 7:30 pm on Friday 9 October.');
    expect(AppState.spokenText('We open at 09:00 and close at 22:00.'), 'We open at 9 am and close at 10 pm.');
    expect(AppState.spokenText('A skin fade is £21.50, ready at 7:30.'), 'A skin fade is £21.50, ready at 7:30.');
    // While a date, time or number is still being written, it isn't said yet (it's said whole).
    expect(AppState.spokenText('Your booking is on 2026-10'), 'Your booking is on');
    expect(AppState.spokenText('Your number is +44770090'), 'Your number is');
    expect(AppState.spokenText('See you at 20:'), 'See you at');
    expect(AppState.spokenText('Table 4'), 'Table 4');
  });

  test('times are said the normal way', () {
    // Heard on a call: "1930 pm", "7, 0, 0pm", "1,930p".
    expect(AppState.spokenText('Would you like to try 1930 pm instead?'), 'Would you like to try 7:30 pm instead?');
    expect(AppState.spokenText('A table at 7:00pm tonight.'), 'A table at 7 pm tonight.');
    expect(AppState.spokenText('Ready by 7.30pm, or 19.30 p.m.'), 'Ready by 7:30 pm, or 7:30 pm');
    expect(AppState.spokenText('Free at 17:30, 18:00 and 21:00.'), 'Free at 5:30 pm, 6 pm and 9 pm.');
    expect(AppState.spokenText('We open at 9am.'), 'We open at 9 am.');
    expect(AppState.spokenText('It costs £7.30 per person.'), 'It costs £7.30 per person.');
  });
}
