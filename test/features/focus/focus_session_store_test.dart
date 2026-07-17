import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orderly_app/features/focus/data/focus_session_store.dart';
import 'package:orderly_app/features/focus/data/focus_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save, read, clear round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusSessionStore(await SharedPreferences.getInstance());
    expect(await store.read(), isNull);

    final snap = FocusSnapshot(
      batchId: 'b1', orderedIds: const ['a'], completedIds: const ['x'],
      skippedIds: const [], sessionTotal: 2, startedAt: DateTime(2026, 7, 17));
    await store.save(snap);

    final back = await store.read();
    expect(back!.batchId, 'b1');
    expect(back.orderedIds, ['a']);

    await store.clear();
    expect(await store.read(), isNull);
  });
}
