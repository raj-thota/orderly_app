import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/notification_id_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns the same id for the same lead+type', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg = NotificationIdRegistry.load(prefs);
    final a = reg.idFor('lead1', 'overdue');
    final b = reg.idFor('lead1', 'overdue');
    expect(a, b);
  });

  test('distinct ids for different lead+type and stays positive', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg = NotificationIdRegistry.load(prefs);
    final ids = {
      reg.idFor('a', 'overdue'),
      reg.idFor('a', 'follow_up'),
      reg.idFor('b', 'overdue'),
    };
    expect(ids, hasLength(3));
    expect(ids.every((id) => id > 0 && id < 0x7fffffff), isTrue);
  });

  test('ids persist across reload after flush', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg1 = NotificationIdRegistry.load(prefs);
    final first = reg1.idFor('lead1', 'overdue');
    await reg1.flush();

    final reg2 = NotificationIdRegistry.load(prefs);
    expect(reg2.idFor('lead1', 'overdue'), first);
    // A new key does not collide with the persisted one.
    expect(reg2.idFor('lead2', 'overdue'), isNot(first));
  });

  test('assignments are not persisted without flush', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg1 = NotificationIdRegistry.load(prefs);
    reg1.idFor('lead1', 'overdue'); // id 1, not flushed
    reg1.idFor('lead2', 'overdue'); // id 2, not flushed

    final reg2 = NotificationIdRegistry.load(prefs);
    // Counter did not persist, so the first new assignment restarts at 1.
    expect(reg2.idFor('lead3', 'overdue'), 1);
  });

  test('load skips malformed entries and reuses valid ones', () async {
    SharedPreferences.setMockInitialValues({
      'notif_id_registry_v1': ['garbage', '=42', 'lead1:overdue=7'],
      'notif_id_registry_counter_v1': 7,
    });
    final prefs = await SharedPreferences.getInstance();
    final reg = NotificationIdRegistry.load(prefs);
    expect(reg.idFor('lead1', 'overdue'), 7); // valid entry reused
    expect(reg.idFor('lead2', 'overdue'), 8); // counter continues past malformed
  });
}
