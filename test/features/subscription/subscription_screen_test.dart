import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';

void main() {
  testWidgets('logs paywall_view on open and paywall_tap on CTA',
      (tester) async {
    final events = <Map<String, dynamic>>[];
    final fake = EventService(
      currentUserId: () => 'u1',
      sink: (row) async => events.add(row),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [eventServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: SubscriptionScreen()),
    ));
    await tester.pumpAndSettle();

    // View is recorded as soon as the paywall opens.
    expect(events.map((e) => e['name']), contains('paywall_view'));
    expect(find.text('Get early access'), findsOneWidget);

    await tester.tap(find.text('Get early access'));
    await tester.pumpAndSettle();

    // Tap is recorded with the price under test, then the door confirms.
    final tap = events.firstWhere((e) => e['name'] == 'paywall_tap');
    expect(tap['props'], {'price': SubscriptionScreen.priceInr});
    expect(find.textContaining("You're on the list"), findsOneWidget);
    expect(find.text('Get early access'), findsNothing);
  });
}
