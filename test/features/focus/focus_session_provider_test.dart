import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/focus/controller/focus_session_provider.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

class _ThrowingSvc implements AiWorkItemsService {
  _ThrowingSvc(this._items);
  final List<AiWorkItem> _items;
  @override
  Future<List<AiWorkItem>> fetchPending() async => _items;
  @override
  Future<void> approve(String id) async => throw Exception('network');
  @override
  Future<void> markDone(String id) async => throw Exception('network');
  @override
  Future<void> dismiss(String id) async {}
  @override
  Future<void> updateStatus(String id, String s) async {}
  @override
  Future<void> triggerGenerate() async {}
}

class _FakeSvc implements AiWorkItemsService {
  _FakeSvc(this._items);
  final List<AiWorkItem> _items;
  final approved = <String>[];
  @override
  Future<List<AiWorkItem>> fetchPending() async => _items;
  @override
  Future<void> approve(String id) async => approved.add(id);
  @override
  Future<void> markDone(String id) async => approved.add(id);
  @override
  Future<void> dismiss(String id) async {}
  @override
  Future<void> updateStatus(String id, String s) async {}
  @override
  Future<void> triggerGenerate() async {}
}

AiWorkItem _i(String id, int score) => AiWorkItem(
    id: id, kind: 'payment_reminder', priority: 'high', score: score,
    title: 't', status: 'pending', batchId: 'b1');

void main() {
  test('start builds a session from pending work items', () async {
    final svc = _FakeSvc([_i('a', 1), _i('b', 2)]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);

    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));

    final state = c.read(focusSessionProvider);
    expect(state.status, FocusStatus.active);
    expect(state.session!.sessionTotal, 2);
    expect(state.session!.current!.id, 'b');
  });

  test('completeCurrent approves via work items and advances', () async {
    final svc = _FakeSvc([_i('a', 2)]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);

    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));
    await c.read(focusSessionProvider.notifier).completeCurrent();

    expect(svc.approved, ['a']); // synced to server/other screens
    expect(c.read(focusSessionProvider).status, FocusStatus.celebrating);
    expect(c.read(focusSessionProvider).session!.isFinished, isTrue);
  });

  test('empty pending yields empty status', () async {
    final svc = _FakeSvc([]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));
    expect(c.read(focusSessionProvider).status, FocusStatus.empty);
  });

  test('completeCurrent surfaces error and stays on task when sync fails', () async {
    final svc = _ThrowingSvc([_i('a', 2)]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));
    await c.read(focusSessionProvider.notifier).completeCurrent();

    final st = c.read(focusSessionProvider);
    expect(st.actionError, isNotNull);
    expect(st.status, FocusStatus.active); // NOT celebrating
    expect(st.session!.current!.id, 'a'); // still on the same task
  });
}
