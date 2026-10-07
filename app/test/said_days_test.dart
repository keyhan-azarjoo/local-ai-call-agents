/// Dates as the caller said them, replayed from real failed test calls (and the clock change).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/ollama.dart';
import 'package:localailine/state/app_state.dart';

void main() {
  final wed = DateTime(2026, 10, 7, 2, 10);
  ChatMessage u(String s) => ChatMessage('user', s);
  ChatMessage a(String s) => ChatMessage('assistant', s);
  const notes = 'Reference notes (from documents ...):\n[1] appointments — live data snapshot: Date: Friday 2026-10-09 · Time: 09:30\n\nQuestion: ';
  test('failing calls', () {
    // barber-0142 / 0145 (notes on the last caller turn, saved via commitWith)
    expect(AppState.saidDays({'date': '2026-10-09'}, [ChatMessage('system', 's'), a('Danny speaking.'), u('${notes}book a kids cut next Thursday at noon with Ali.')], now: wed)['date'], '2026-10-08');
    expect(AppState.saidDays({'date': '2026-10-10'}, [a('Danny speaking.'), u('${notes}Hi, I would like a cut next Thursday at 9:30'), a('Next Thursday at 9:30 with Jay is free. Booked.')], now: wed)['date'], '2026-10-08');
    // barber-0144: Wednesday said on a Wednesday
    expect(AppState.saidDays({'date': '2026-10-08'}, [u('hot towel shave on Wednesday at quarter past three pm.'), a('...on Wednesday at 3:15 PM. Booked.')], now: wed)['date'], '2026-10-07');
    // barber-0146: model's own "Next Thursday is 2026-10-10" is no offer
    expect(AppState.saidDays({'date': '2026-10-10'}, [u('beard trim next Thursday at 5pm.'), a('Next Thursday is 2026-10-10. Tony is free at 5pm. Book?'), u('Yes.')], now: wed)['date'], '2026-10-08');
    // garage-0556
    expect(AppState.saidDays({'date': '2026-10-08'}, [u('interim service the day after tomorrow.'), a("That's Thursday, 2026-10-08. Confirm?"), u("${notes}Yes, that's correct. I'll be dropping it off the day after tomorrow.")], now: wed)['date'], '2026-10-09');
    // restaurant-0005
    expect(AppState.saidDays({'date': '2026-10-10'}, [u('The day after tomorrow, ten past seven pm.'), a('a table at 7:10 pm on Friday the 10th'), u('No. Four people.'), a('table for four on Friday the 10th. Is that right?'), u('Yes. It is a birthday.')], now: wed)['date'], '2026-10-09');
    // hotel-0453
    final h = AppState.saidDays({'check_in': '2026-10-14', 'check_out': '2026-10-15'}, [u('a Family Suite for next Thursday for one night'), a('Next Thursday is 2026-10-14. Is that correct?'), u("Yes, that's correct.")], now: wed);
    expect([h['check_in'], h['check_out']], ['2026-10-08', '2026-10-09']);
    // a real offer stays: Thursday full, Friday offered, yes
    expect(AppState.saidDays({'date': '2026-10-09'}, [u('a table Thursday at 7pm'), a('Thursday is full; Friday at 7pm is free. Shall I book it?'), u('Yes please')], now: wed)['date'], '2026-10-09');
    // nights fixed even when check-in is right
    final s = AppState.saidDays({'check_in': '2026-10-08', 'check_out': '2026-10-09'}, [u('tomorrow for three nights')], now: wed);
    expect(s['check_out'], '2026-10-11');
  });
  test('clocks change', () {
    expect(spokenDates('tomorrow', now: DateTime(2026, 10, 25, 9)), {'2026-10-26'});
    expect(spokenDates('the day after tomorrow', now: DateTime(2026, 10, 24, 9)), {'2026-10-26'});
    expect(spokenDates('next Thursday at 10am', now: wed), {'2026-10-08', '2026-10-15'});
    expect(spokenDates('this Wednesday', now: wed), {'2026-10-07', '2026-10-14'});
    expect(AppState.calendar(wed), contains('the week after: Thursday 2026-10-15'));
  });
}
