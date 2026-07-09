import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';

void main() {
  group('EventService.track', () {
    test('writes name, user_id and props', () async {
      Map<String, dynamic>? row;
      final svc = EventService(
        currentUserId: () => 'u1',
        sink: (r) async => row = r,
      );

      await svc.track('paywall_tap', props: {'price': 299});

      expect(row, {
        'user_id': 'u1',
        'name': 'paywall_tap',
        'props': {'price': 299},
      });
    });

    test('defaults props to an empty map', () async {
      Map<String, dynamic>? row;
      final svc = EventService(
        currentUserId: () => 'u1',
        sink: (r) async => row = r,
      );

      await svc.track('signup_completed');

      expect(row!['props'], <String, dynamic>{});
    });

    test('is a no-op when signed out', () async {
      var called = false;
      final svc = EventService(
        currentUserId: () => null,
        sink: (_) async => called = true,
      );

      await svc.track('paywall_view');

      expect(called, isFalse);
    });

    test('swallows sink errors so a flow never breaks', () async {
      final svc = EventService(
        currentUserId: () => 'u1',
        sink: (_) async => throw Exception('network down'),
      );

      // Must complete normally despite the sink throwing.
      await expectLater(svc.track('order_created'), completes);
    });
  });
}
