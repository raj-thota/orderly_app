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
  String? lastPlan;
  _FakeCheckoutSvc({this.uri});
  @override
  Future<Uri> createCheckout({
    required String gateway,
    required String plan,
  }) async {
    lastGateway = gateway;
    lastPlan = plan;
    return uri ?? Uri.parse('https://checkout.example.com');
  }
}

Widget _wrap({Subscription? sub, _FakeCheckoutSvc? checkoutSvc}) {
  return ProviderScope(
    overrides: [
      subscriptionServiceProvider.overrideWithValue(_FakeSubSvc(sub)),
      checkoutServiceProvider.overrideWithValue(
        checkoutSvc ?? _FakeCheckoutSvc(),
      ),
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
  currentPeriodEnd: DateTime(2026, 8, 22),
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('shows Pro plan with 499 price', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.textContaining('499'), findsWidgets);
    expect(find.textContaining('Pro'), findsWidgets);
  });

  testWidgets('shows the free-forever card', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.text('Free forever'), findsOneWidget);
    expect(find.textContaining('Unlimited orders'), findsOneWidget);
  });

  testWidgets('shows WhatsApp tier as coming soon with 999', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.text('Pro + WhatsApp'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.textContaining('999'), findsWidgets);
  });

  testWidgets('gated user sees subscribe CTA and trial-ended note', (t) async {
    await t.pumpWidget(_wrap(sub: null));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cta_start_trial')), findsOneWidget);
    expect(find.textContaining('trial has ended'), findsOneWidget);
  });

  testWidgets('shows trial badge with days left when trialing', (t) async {
    await t.pumpWidget(_wrap(sub: _trialSub()));
    await t.pumpAndSettle();
    expect(find.textContaining('Trial ·'), findsOneWidget);
    expect(find.textContaining('days left'), findsWidgets);
  });

  testWidgets('active subscriber gets manage, never a checkout CTA', (t) async {
    await t.pumpWidget(_wrap(sub: _activeSub()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cta_manage')), findsOneWidget);
    expect(find.byKey(const Key('cta_start_trial')), findsNothing);
    expect(find.textContaining('Renews on 22/8/2026'), findsOneWidget);
  });

  testWidgets('tapping subscribe checks out pro_monthly on razorpay', (
    t,
  ) async {
    final checkoutSvc = _FakeCheckoutSvc(
      uri: Uri.parse('https://rzp.io/subscribe'),
    );
    await t.pumpWidget(_wrap(sub: null, checkoutSvc: checkoutSvc));
    await t.pumpAndSettle();

    await t.ensureVisible(find.byKey(const Key('cta_start_trial')));
    await t.tap(find.byKey(const Key('cta_start_trial')));
    await t.pumpAndSettle();

    expect(checkoutSvc.lastGateway, 'razorpay');
    expect(checkoutSvc.lastPlan, 'pro_monthly');
  });
}
