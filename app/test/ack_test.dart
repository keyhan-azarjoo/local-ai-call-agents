import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/state/app_state.dart';

void main() {
  test('acknowledgements fit the request', () {
    expect(AppEngine.ackFor('So can you tell me how many users do I have?', 'en'), contains('users'));
    expect(AppEngine.ackFor('How much is delivery to RV3?', 'en'), contains('delivery'));
    expect(AppEngine.ackFor('Can you list the user groups and who is in each one?', 'en'), contains('user groups'));
    expect(AppEngine.ackFor('Hello, who are you?', 'en'), isNull);
    expect(AppEngine.ackFor('Thanks a lot', 'en'), isNull);
    expect(AppEngine.ackFor('Book a table for four tomorrow at 7', 'en'), isNotNull);
    expect(AppEngine.ackFor('چند تا کاربر در سیستم دارم؟', 'fa'), contains('بشمار'));
    expect(AppEngine.ackFor('سلام خوبی؟', 'fa'), isNull);
    for (final q in ['So can you tell me how many users do I have?', 'How much is delivery to RV3?', 'Can you list the user groups and who is in each one?', 'What time do you close on Sunday?', 'Show me my orders from yesterday']) {
      // ignore: avoid_print
      print('$q -> ${AppEngine.ackFor(q, 'en')}');
    }
  });

  test('no "let me check" before a thank-you or goodbye', () {
    expect(AppEngine.ackFor("Great, thanks Julia. I'll be there at 7:30 pm.", 'en'), isNull);
    expect(AppEngine.ackFor("I'll call 111 then. Thank you.", 'en'), isNull);
    expect(AppEngine.ackFor('Can I book a table for two at 8?', 'en'), isNotNull);
  });
}
