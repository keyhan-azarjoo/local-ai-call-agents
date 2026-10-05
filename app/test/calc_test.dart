import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/agent_loop.dart';

void main() {
  test('calculator', () {
    expect(Calc.eval('2*16.00 + 3.95'), closeTo(35.95, 1e-9));
    expect(Calc.eval('£15.50 × 2 + (4 + 4.5)'), closeTo(39.5, 1e-9));
    expect(Calc.eval('-3 + 10 / 4'), closeTo(-0.5, 1e-9));
    expect(Calc.eval('2 ** 3'), isNull);
    expect(Calc.eval('import os'), isNull);
    expect(Calc.eval('1/0'), isNull);
    expect(Calc.format(35.95), '35.95');
    expect(Calc.format(32), '32');
  });
}
