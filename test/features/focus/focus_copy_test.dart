import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_copy.dart';

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  test('entry line mentions task count and stays short', () {
    final line = focusEntryLine(5);
    expect(line, contains('5'));
    expect(_words(line), lessThanOrEqualTo(10));
  });

  test('task lead differs by group and stays short', () {
    expect(focusTaskLead('overdue_payment', 'Aman'), contains('payment'));
    expect(focusTaskLead('reply', 'Meera'), contains('Meera'));
    expect(_words(focusTaskLead('offer', 'Karan')), lessThanOrEqualTo(8));
  });

  test('success line reflects remaining', () {
    expect(focusSuccessLine(3), contains('3'));
    expect(_words(focusSuccessLine(1)), lessThanOrEqualTo(8));
  });

  test('finish line greets by name', () {
    expect(focusFinishLine('Rahul'), contains('Rahul'));
  });
}
