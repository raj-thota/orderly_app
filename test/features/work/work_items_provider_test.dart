import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

AiWorkItem _item(String id, {String priority = 'high'}) => AiWorkItem(
      id: id,
      kind: 'payment_reminder',
      priority: priority,
      score: 80,
      title: 'Payment pending',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-$id',
      customerName: 'Customer $id',
    );

class FakeAiWorkItemsService implements AiWorkItemsService {
  final List<AiWorkItem> _items;
  final Map<String, String> updates = {};
  bool generateCalled = false;
  bool throwOnApprove;

  FakeAiWorkItemsService(this._items, {this.throwOnApprove = false});

  @override
  Future<List<AiWorkItem>> fetchPending() async => List.from(_items);

  @override
  Future<void> updateStatus(String id, String status) async =>
      updates[id] = status;

  @override
  Future<void> approve(String id) async {
    if (throwOnApprove) throw Exception('network error');
    updates[id] = 'approved';
  }

  @override
  Future<void> dismiss(String id) => updateStatus(id, 'dismissed');

  @override
  Future<void> markDone(String id) => updateStatus(id, 'done');

  @override
  Future<void> triggerGenerate() async => generateCalled = true;
}

// ─── Helper ───────────────────────────────────────────────────────────────────

ProviderContainer makeContainer([FakeAiWorkItemsService? svc]) =>
    ProviderContainer(overrides: [
      aiWorkItemsServiceProvider
          .overrideWithValue(svc ?? FakeAiWorkItemsService([])),
    ]);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  test('load populates items from service', () async {
    final svc = FakeAiWorkItemsService([_item('1'), _item('2')]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);

    await c.read(workItemsProvider.notifier).load();

    final state = c.read(workItemsProvider);
    expect(state.items, hasLength(2));
    expect(state.items.first.id, '1');
  });

  test('loading flag transitions correctly', () async {
    final c = makeContainer(FakeAiWorkItemsService([]));
    addTearDown(c.dispose);

    expect(c.read(workItemsProvider).loading, isFalse);
    final fut = c.read(workItemsProvider.notifier).load();
    expect(c.read(workItemsProvider).loading, isTrue);
    await fut;
    expect(c.read(workItemsProvider).loading, isFalse);
  });

  test('approve removes item optimistically and persists', () async {
    final svc = FakeAiWorkItemsService([_item('1'), _item('2')]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).approve('1');

    expect(c.read(workItemsProvider).items.any((i) => i.id == '1'), isFalse);
    expect(svc.updates['1'], 'approved');
  });

  test('dismiss removes item optimistically and persists', () async {
    final svc = FakeAiWorkItemsService([_item('1'), _item('2')]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).dismiss('1');

    expect(c.read(workItemsProvider).items.any((i) => i.id == '1'), isFalse);
    expect(svc.updates['1'], 'dismissed');
  });

  test('markDone removes item and persists', () async {
    final svc = FakeAiWorkItemsService([_item('1')]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).markDone('1');

    expect(c.read(workItemsProvider).items, isEmpty);
    expect(svc.updates['1'], 'done');
  });

  test('highItems / mediumItems / lowItems filter by priority', () async {
    final svc = FakeAiWorkItemsService([
      _item('1', priority: 'high'),
      _item('2', priority: 'medium'),
      _item('3', priority: 'low'),
      _item('4', priority: 'high'),
    ]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    final state = c.read(workItemsProvider);
    expect(state.highItems, hasLength(2));
    expect(state.mediumItems, hasLength(1));
    expect(state.lowItems, hasLength(1));
  });

  test('pendingCount equals total items', () async {
    final svc = FakeAiWorkItemsService([
      _item('1'),
      _item('2', priority: 'low'),
    ]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    expect(c.read(workItemsProvider).pendingCount, 2);
  });

  test('rollback restores item list on approve failure', () async {
    final svc =
        FakeAiWorkItemsService([_item('1'), _item('2')], throwOnApprove: true);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).approve('1');

    // Items should be restored after failure.
    expect(c.read(workItemsProvider).items, hasLength(2));
  });
}
