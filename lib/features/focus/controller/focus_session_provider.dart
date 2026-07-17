import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/focus_session.dart';
import '../../work/controller/work_items_provider.dart';

enum FocusStatus { entry, resume, active, celebrating, finished, empty }

class FocusModeState {
  const FocusModeState({
    this.session,
    this.status = FocusStatus.entry,
    this.sending = false,
    this.actionError,
  });

  final FocusSession? session;
  final FocusStatus status;
  final bool sending;
  final String? actionError;

  FocusModeState copyWith({
    FocusSession? session,
    FocusStatus? status,
    bool? sending,
    String? Function()? actionError,
  }) =>
      FocusModeState(
        session: session ?? this.session,
        status: status ?? this.status,
        sending: sending ?? this.sending,
        actionError: actionError != null ? actionError() : this.actionError,
      );
}

class FocusSessionNotifier extends StateNotifier<FocusModeState> {
  FocusSessionNotifier(this._ref) : super(const FocusModeState());
  final Ref _ref;

  Future<void> start({required DateTime now}) async {
    final items = _ref.read(workItemsProvider).items;
    if (items.isEmpty) {
      state = const FocusModeState(status: FocusStatus.empty);
      return;
    }
    final batchId = items.first.batchId;
    final session = FocusSession.start(items, now: now, batchId: batchId);
    state = FocusModeState(session: session, status: FocusStatus.active);
  }

  Future<void> completeCurrent({bool markDone = false}) async {
    final s = state.session;
    if (s?.current == null) return;
    final id = s!.current!.id;
    state = state.copyWith(sending: true, actionError: () => null);
    try {
      final work = _ref.read(workItemsProvider.notifier);
      markDone ? await work.markDone(id) : await work.approve(id);
      state = state.copyWith(
          session: s.complete(),
          status: FocusStatus.celebrating,
          sending: false);
    } catch (e) {
      state = state.copyWith(sending: false, actionError: () => e.toString());
    }
  }

  /// Called by the UI after the success animation to reveal the next task.
  void advance() {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(
        status: s.isFinished ? FocusStatus.finished : FocusStatus.active);
  }

  void skipCurrent() {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(session: s.skip(), status: FocusStatus.active);
  }

  void clearError() => state = state.copyWith(actionError: () => null);
}

final focusSessionProvider =
    StateNotifierProvider<FocusSessionNotifier, FocusModeState>(
  (ref) => FocusSessionNotifier(ref),
);
