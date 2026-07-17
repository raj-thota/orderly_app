import 'package:orderly_app/features/today/data/brief_narrative.dart'
    show estimatedMinutesFor;
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// Immutable snapshot of a guided Focus Mode run. Pure — no Flutter, no I/O.
class FocusSession {
  const FocusSession({
    required this.queue,
    required this.completed,
    required this.skippedIds,
    required this.sessionTotal,
    required this.startedAt,
    required this.batchId,
  });

  /// Not-yet-done items, current task first. Skips move to the tail.
  final List<AiWorkItem> queue;

  /// Items finished this session, in completion order.
  final List<AiWorkItem> completed;

  /// Ids skipped at least once (a task may be skipped only once).
  final Set<String> skippedIds;

  /// Denominator for progress — frozen at start so it never shifts.
  final int sessionTotal;

  /// When this session began.
  final DateTime startedAt;

  /// The work-item batch this session was built from.
  final String batchId;

  factory FocusSession.start(
    List<AiWorkItem> pending, {
    required DateTime now,
    required String batchId,
  }) {
    final ordered = [...pending]..sort((a, b) => b.score.compareTo(a.score));
    return FocusSession(
      queue: ordered,
      completed: const [],
      skippedIds: const {},
      sessionTotal: ordered.length,
      startedAt: now,
      batchId: batchId,
    );
  }

  AiWorkItem? get current => queue.isEmpty ? null : queue.first;
  int get completedCount => completed.length;
  double get progress => sessionTotal == 0 ? 0 : completedCount / sessionTotal;

  /// 1-based index of the current task within the frozen total.
  int get position => completedCount + 1;
  bool get isEmpty => sessionTotal == 0;
  bool get isFinished => sessionTotal > 0 && queue.isEmpty;

  /// A task can be skipped only if it is not the last one and has not been
  /// skipped before — so a skipped task always resurfaces and must be handled.
  bool get canSkip =>
      queue.length > 1 && current != null && !skippedIds.contains(current!.id);

  int get remainingMinutes =>
      queue.fold(0, (sum, i) => sum + estimatedMinutesFor(i));

  FocusSession complete() {
    if (current == null) return this;
    return copyWith(
      queue: queue.sublist(1),
      completed: [...completed, current!],
    );
  }

  FocusSession skip() {
    if (!canSkip) return this;
    final head = queue.first;
    return copyWith(
      queue: [...queue.sublist(1), head],
      skippedIds: {...skippedIds, head.id},
    );
  }

  FocusSession copyWith({
    List<AiWorkItem>? queue,
    List<AiWorkItem>? completed,
    Set<String>? skippedIds,
  }) =>
      FocusSession(
        queue: queue ?? this.queue,
        completed: completed ?? this.completed,
        skippedIds: skippedIds ?? this.skippedIds,
        sessionTotal: sessionTotal,
        startedAt: startedAt,
        batchId: batchId,
      );
}
