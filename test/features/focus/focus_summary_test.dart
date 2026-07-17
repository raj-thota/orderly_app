import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _i(String id, String kind, {double? amount}) => AiWorkItem(
    id: id, kind: kind, priority: 'high', score: 0, title: 't',
    status: 'pending', batchId: 'b1', amount: amount);

void main() {
  test('summary tallies completed items by group', () {
    var s = FocusSession.start([
      _i('a', 'overdue_payment', amount: 8597),
      _i('b', 'payment_reminder', amount: 10803),
      _i('c', 'reply'),
      _i('d', 'follow_up'),
      _i('e', 'offer'),
    ], now: DateTime(2026, 7, 17), batchId: 'b1');
    for (var k = 0; k < 5; k++) {
      s = s.complete();
    }
    final sum = s.summary();
    expect(sum.tasksCompleted, 5);
    expect(sum.paymentsFollowedUp, 2);
    expect(sum.amountFollowedUp, 19400);
    expect(sum.repliesSent, 2);
    expect(sum.offersSent, 1);
  });
}
