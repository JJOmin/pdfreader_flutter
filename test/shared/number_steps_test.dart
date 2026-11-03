// The speed reader's text settings as numbers with − and + (PLAN 18.6).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/number_steps.dart';

void main() {
  const size = (14.0, 40.0, 1.0);
  const line = (1.2, 2.6, 0.1);
  const letters = (-0.08, 0.2, 0.01);

  test('a step moves by the setting’s step and stops at its ends', () {
    expect(stepped(18, size, 1), 19);
    expect(stepped(40, size, 1), 40);
    expect(stepped(14, size, -1), 14);
    expect(stepped(1.5, line, 1), 1.6);
    expect(stepped(0, letters, -1), -0.01);
  });

  test('a step lands on the grid even from a value between two steps', () {
    expect(stepped(1.55, line, 1), 1.6);
    expect(stepped(1.55, line, -1), 1.5);
    expect(stepped(18.4, size, 1), 19);
  });

  test('typed text is read as a number, with a comma too, and kept inside the limits', () {
    expect(parsedNumber('22', size), 22);
    expect(parsedNumber(' 1,8 ', line), 1.8);
    expect(parsedNumber('99', size), 40);
    expect(parsedNumber('-1', letters), -0.08);
    expect(parsedNumber('abc', size), isNull);
    expect(parsedNumber('', size), isNull);
  });

  test('shows as many decimals as the step has', () {
    expect(shownNumber(18, size), '18');
    expect(shownNumber(1.6000000000000001, line), '1.6');
    expect(shownNumber(-0.01, letters), '-0.01');
  });
}
