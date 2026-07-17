import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_snapshot.dart';

void main() {
  final snap = FocusSnapshot(
    batchId: 'b1',
    orderedIds: const ['a', 'b'],
    completedIds: const ['x', 'y', 'z'],
    skippedIds: const ['a'],
    sessionTotal: 5,
    startedAt: DateTime(2026, 7, 17, 9),
  );

  test('round-trips through JSON', () {
    final back = FocusSnapshot.fromJson(snap.toJson());
    expect(back.batchId, 'b1');
    expect(back.orderedIds, ['a', 'b']);
    expect(back.completedIds, ['x', 'y', 'z']);
    expect(back.skippedIds, ['a']);
    expect(back.sessionTotal, 5);
    expect(back.startedAt, DateTime(2026, 7, 17, 9));
  });

  test('resumable only when batch matches, same day, and work remains', () {
    final now = DateTime(2026, 7, 17, 14);
    expect(snap.isResumable(currentBatchId: 'b1', now: now), isTrue);
    expect(snap.isResumable(currentBatchId: 'b2', now: now), isFalse);
    expect(snap.isResumable(currentBatchId: 'b1', now: DateTime(2026, 7, 18, 9)),
        isFalse);
    final done = FocusSnapshot(
      batchId: 'b1', orderedIds: const [], completedIds: const ['x'],
      skippedIds: const [], sessionTotal: 1, startedAt: DateTime(2026, 7, 17));
    expect(done.isResumable(currentBatchId: 'b1', now: now), isFalse);
  });
}
