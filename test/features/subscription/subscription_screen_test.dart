import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/checkout_service.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/subscription/data/subscription_service.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';

class _FakeSubSvc implements SubscriptionService {
  final Subscription? sub;
  _FakeSubSvc(this.sub);
  @override
  Stream<Subscription?> watchSubscription() => Stream.value(sub);
  @override
  Future<void> ensureTrial() async {}
}

class _FakeCheckoutSvc implements CheckoutService {
  Uri? uri;
  String? lastGateway;
  _FakeCheckoutSvc({this.uri});
  @override
  Future<Uri> createCheckout({required String gateway}) async {
    lastGateway = gateway;
    return uri ?? Uri.parse('https://checkout.example.com');
  }
}

Widget _wrap({Subscription? sub, _FakeCheckoutSvc? checkoutSvc}) {
  return ProviderScope(
    overrides: [
      subscriptionServiceProvider.overrideWithValue(_FakeSubSvc(sub)),
      checkoutServiceProvider
          .overrideWithValue(checkoutSvc ?? _FakeCheckoutSvc()),
    ],
    child: const MaterialApp(home: SubscriptionScreen()),
  );
}

Subscription _trialSub() => Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'pro_monthly',
      status: 'trialing',
      trialEnd: DateTime.now().add(const Duration(days: 7)),
      createdAt: DateTime(2026, 1, 1),
    );

Subscription _activeSub() => Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'pro_monthly',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('shows Pro plan with 999 price', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.textContaining('999'), findsWidgets);
    expect(find.textContaining('Pro'), findsWidgets);
  });

  testWidgets('shows Business Coming soon card', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.textContaining('Business'), findsWidgets);
    expect(find.textContaining('soon'), findsWidgets);
  });

  testWidgets('shows Start Free Trial when gated (no subscription)', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cta_start_trial')), findsOneWidget);
  });

  testWidgets('shows trial active badge when trialing', (t) async {
    await t.pumpWidget(_wrap(sub: _trialSub()));
    await t.pumpAndSettle();
    expect(find.textContaining('Trial'), findsWidgets);
  });

  testWidgets('shows Manage button when active', (t) async {
    await t.pumpWidget(_wrap(sub: _activeSub()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cta_manage')), findsOneWidget);
  });

  testWidgets('tapping Start Free Trial calls checkout service', (t) async {
    final checkoutSvc =
        _FakeCheckoutSvc(uri: Uri.parse('https://rzp.io/subscribe'));
    await t.pumpWidget(_wrap(sub: null, checkoutSvc: checkoutSvc));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('cta_start_trial')));
    await t.pumpAndSettle();

    expect(checkoutSvc.lastGateway, 'razorpay');
  });
}
