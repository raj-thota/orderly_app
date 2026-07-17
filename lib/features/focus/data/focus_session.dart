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
  final DateTime startedAt;
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
