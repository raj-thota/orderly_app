/// Serialisable view of an in-progress session, persisted for resume.
class FocusSnapshot {
  const FocusSnapshot({
    required this.batchId,
    required this.orderedIds,
    required this.completedIds,
    required this.skippedIds,
    required this.sessionTotal,
    required this.startedAt,
  });

  final String batchId;
  final List<String> orderedIds;
  final List<String> completedIds;
  final List<String> skippedIds;
  final int sessionTotal;
  final DateTime startedAt;

  int get remaining => orderedIds.length;

  bool isResumable({required String currentBatchId, required DateTime now}) =>
      batchId == currentBatchId &&
      remaining > 0 &&
      startedAt.year == now.year &&
      startedAt.month == now.month &&
      startedAt.day == now.day;

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'orderedIds': orderedIds,
        'completedIds': completedIds,
        'skippedIds': skippedIds,
        'sessionTotal': sessionTotal,
        'startedAt': startedAt.toIso8601String(),
      };

  factory FocusSnapshot.fromJson(Map<String, dynamic> json) => FocusSnapshot(
        batchId: json['batchId'] as String,
        orderedIds: (json['orderedIds'] as List).cast<String>(),
        completedIds: (json['completedIds'] as List).cast<String>(),
        skippedIds: (json['skippedIds'] as List).cast<String>(),
        sessionTotal: json['sessionTotal'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}
