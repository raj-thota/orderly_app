import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _item(String id, {String kind = 'payment_reminder', int score = 0, double? amount}) =>
    AiWorkItem(
      id: id, kind: kind, priority: 'high', score: score, title: 't',
      status: 'pending', batchId: 'b1', amount: amount,
    );

void main() {
  final now = DateTime(2026, 7, 17, 9);

  test('start freezes total and orders by score desc', () {
    final s = FocusSession.start(
      [_item('a', score: 1), _item('b', score: 5), _item('c', score: 3)],
      now: now, batchId: 'b1',
    );
    expect(s.sessionTotal, 3);
    expect(s.queue.map((i) => i.id).toList(), ['b', 'c', 'a']);
    expect(s.current!.id, 'b');
    expect(s.completedCount, 0);
    expect(s.progress, 0);
    expect(s.position, 1);
    expect(s.isEmpty, isFalse);
    expect(s.isFinished, isFalse);
  });

  test('empty session', () {
    final s = FocusSession.start([], now: now, batchId: 'b1');
    expect(s.isEmpty, isTrue);
    expect(s.current, isNull);
    expect(s.progress, 0);
  });

  test('complete moves current to completed and advances', () {
    var s = FocusSession.start(
      [_item('a', score: 3), _item('b', score: 2)], now: now, batchId: 'b1');
    s = s.complete();
    expect(s.completedCount, 1);
    expect(s.current!.id, 'b');
    expect(s.progress, 0.5);
    expect(s.position, 2);
    s = s.complete();
    expect(s.isFinished, isTrue);
    expect(s.current, isNull);
    expect(s.progress, 1);
  });

  test('skip requeues current to tail and can only skip once', () {
    var s = FocusSession.start(
      [_item('a', score: 3), _item('b', score: 2)], now: now, batchId: 'b1');
    expect(s.canSkip, isTrue);
    s = s.skip();
    expect(s.current!.id, 'b');
    expect(s.queue.map((i) => i.id).toList(), ['b', 'a']);
    expect(s.skippedIds, contains('a'));
    s = s.complete(); // finish b
    expect(s.current!.id, 'a');
    expect(s.canSkip, isFalse); // already skipped + last item
  });

  test('remaining minutes sums per-kind estimate over the queue', () {
    final s = FocusSession.start(
      [_item('a', kind: 'payment_reminder'), _item('b', kind: 'reply')],
      now: now, batchId: 'b1'); // 2 + 3
    expect(s.remainingMinutes, 5);
  });
}
