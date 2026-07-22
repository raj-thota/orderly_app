import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orderly_app/features/focus/presentation/focus_mode_route.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

class _Svc implements AiWorkItemsService {
  @override
  Future<List<AiWorkItem>> fetchPending() async => const [AiWorkItem(
    id: 'a', kind: 'overdue_payment', priority: 'high', score: 9, title: 't',
    status: 'pending', batchId: 'b1', customerName: 'Aman Gupta', amount: 8597)];
  @override
  Future<void> approve(String id) async {}
  @override
  Future<void> markDone(String id) async {}
  @override
  Future<void> dismiss(String id) async {}
  @override
  Future<void> updateStatus(String id, String s) async {}
  @override
  Future<void> triggerGenerate() async {}
  @override
  Future<void> createFromCapture({
    required String kind,
    required String priority,
    required int score,
    required String title,
    String? customerId,
    String? leadId,
    String? orderId,
    String? context,
    double? amount,
    double? confidence,
  }) async {}
}

void main() {
  testWidgets('opens entry when work exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(_Svc()),
    ], child: const MaterialApp(home: FocusModeView())));
    // Use bounded pump instead of pumpAndSettle — the entry screen contains
    // Orbit's repeating bob animation which never settles, causing
    // pumpAndSettle to time out. A single 350ms pump is sufficient to let
    // the async initState (SharedPreferences + provider load) complete and
    // the entry screen render, without chasing the infinite animation loop.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('focus_start')), findsOneWidget);
  });
}
