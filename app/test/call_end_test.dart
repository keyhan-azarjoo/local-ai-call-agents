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
}
