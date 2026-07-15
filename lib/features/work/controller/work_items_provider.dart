import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai_work_item.dart';
import '../data/ai_work_items_service.dart';

// ─── Service provider ─────────────────────────────────────────────────────────

final aiWorkItemsServiceProvider =
    Provider<AiWorkItemsService>((_) => SupabaseAiWorkItemsService());

// ─── State ────────────────────────────────────────────────────────────────────

class WorkItemsState {
  const WorkItemsState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<AiWorkItem> items;
  final bool loading;
  final String? error;

  List<AiWorkItem> get highItems => items.where((i) => i.isHigh).toList();
  List<AiWorkItem> get mediumItems => items.where((i) => i.isMedium).toList();
  List<AiWorkItem> get lowItems => items.where((i) => i.isLow).toList();
  int get pendingCount => items.length;

  WorkItemsState copyWith({
    List<AiWorkItem>? items,
    bool? loading,
    String? Function()? error,
  }) =>
      WorkItemsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class WorkItemsNotifier extends StateNotifier<WorkItemsState> {
  WorkItemsNotifier(this._svc) : super(const WorkItemsState());

  final AiWorkItemsService _svc;

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final items = await _svc.fetchPending();
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      state = state.copyWith(
          loading: false, error: () => e.toString(), items: []);
    }
  }

  Future<void> approve(String id) async {
    final prev = state.items;
    // Optimistic removal.
    state = state.copyWith(
        items: prev.where((i) => i.id != id).toList());
    try {
      await _svc.approve(id);
    } catch (_) {
      // Rollback.
      state = state.copyWith(items: prev);
    }
  }

  Future<void> dismiss(String id) async {
    final prev = state.items;
    state = state.copyWith(
        items: prev.where((i) => i.id != id).toList());
    try {
      await _svc.dismiss(id);
    } catch (_) {
      state = state.copyWith(items: prev);
    }
  }

  Future<void> markDone(String id) async {
    final prev = state.items;
    state = state.copyWith(
        items: prev.where((i) => i.id != id).toList());
    try {
      await _svc.markDone(id);
    } catch (_) {
      state = state.copyWith(items: prev);
    }
  }

  Future<void> triggerGenerate() => _svc.triggerGenerate();
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final workItemsProvider =
    StateNotifierProvider<WorkItemsNotifier, WorkItemsState>(
  (ref) => WorkItemsNotifier(ref.watch(aiWorkItemsServiceProvider)),
);
