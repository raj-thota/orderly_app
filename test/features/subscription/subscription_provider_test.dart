import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/checkout_service.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/subscription/data/subscription_service.dart';

class FakeSubscriptionService implements SubscriptionService {
  final Subscription? sub;
  int ensureTrialCalled = 0;

  FakeSubscriptionService({this.sub});

  @override
  Stream<Subscription?> watchSubscription() => Stream.value(sub);

  @override
  Future<void> ensureTrial() async => ensureTrialCalled++;
}

class FakeCheckoutService implements CheckoutService {
  Uri? returnedUri;
  String? lastGateway;
  bool shouldThrow = false;

  FakeCheckoutService({this.returnedUri});

  String? lastPlan;

  @override
  Future<Uri> createCheckout({
    required String gateway,
    required String plan,
  }) async {
    lastGateway = gateway;
    lastPlan = plan;
    if (shouldThrow) throw Exception('checkout_failed');
    return returnedUri ?? Uri.parse('https://checkout.example.com');
  }
}

ProviderContainer _makeContainer({
  Subscription? sub,
  FakeCheckoutService? checkoutSvc,
}) {
  final subSvc = FakeSubscriptionService(sub: sub);
  final chkSvc = checkoutSvc ?? FakeCheckoutService();
  return ProviderContainer(
    overrides: [
      subscriptionServiceProvider.overrideWithValue(subSvc),
      checkoutServiceProvider.overrideWithValue(chkSvc),
    ],
  );
}

void main() {
  test('subscriptionProvider emits the subscription from service', () async {
    final activeSub = Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'pro_monthly',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );
    final container = _makeContainer(sub: activeSub);
    addTearDown(container.dispose);

    final async = await container.read(subscriptionProvider.future);
    expect(async?.status, 'active');
  });

  test('subscriptionProvider emits null when no subscription exists', () async {
    final container = _makeContainer(sub: null);
    addTearDown(container.dispose);

    final result = await container.read(subscriptionProvider.future);
    expect(result, isNull);
  });

  test('aiAccessProvider is true for an active Pro subscription', () async {
    final activeSub = Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'pro_monthly',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );
    final container = _makeContainer(sub: activeSub);
    addTearDown(container.dispose);

    // Wait for stream to emit
    await container.read(subscriptionProvider.future);
    expect(container.read(aiAccessProvider), isTrue);
  });

  test('aiAccessProvider defaults to false when no subscription', () async {
    final container = _makeContainer(sub: null);
    addTearDown(container.dispose);

    await container.read(subscriptionProvider.future);
    expect(container.read(aiAccessProvider), isFalse);
  });

  test('aiAccessProvider is true during a valid trial', () async {
    final trialSub = Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'pro_monthly',
      status: 'trialing',
      trialEnd: DateTime.now().add(const Duration(days: 7)),
      createdAt: DateTime(2026, 1, 1),
    );
    final container = _makeContainer(sub: trialSub);
    addTearDown(container.dispose);

    await container.read(subscriptionProvider.future);
    expect(container.read(aiAccessProvider), isTrue);
  });

  test('aiAccessProvider is false for an active non-AI plan', () async {
    final starterSub = Subscription(
      id: 's1',
      userId: 'u1',
      plan: 'starter_monthly',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );
    final container = _makeContainer(sub: starterSub);
    addTearDown(container.dispose);

    await container.read(subscriptionProvider.future);
    expect(container.read(aiAccessProvider), isFalse);
  });

  test(
    'checkoutController.startCheckout calls service and returns url',
    () async {
      final svc = FakeCheckoutService(
        returnedUri: Uri.parse('https://rzp.io/subscribe'),
      );
      final container = _makeContainer(checkoutSvc: svc);
      addTearDown(container.dispose);

      final uri = await container
          .read(checkoutControllerProvider.notifier)
          .startCheckout(gateway: 'razorpay', plan: 'pro_monthly');

      expect(uri?.toString(), 'https://rzp.io/subscribe');
      expect(svc.lastGateway, 'razorpay');
      expect(svc.lastPlan, 'pro_monthly');
      expect(container.read(checkoutControllerProvider).loading, isFalse);
    },
  );

  test('checkoutController sets error on service failure', () async {
    final svc = FakeCheckoutService()..shouldThrow = true;
    final container = _makeContainer(checkoutSvc: svc);
    addTearDown(container.dispose);

    final uri = await container
        .read(checkoutControllerProvider.notifier)
        .startCheckout(gateway: 'razorpay', plan: 'pro_monthly');

    expect(uri, isNull);
    expect(container.read(checkoutControllerProvider).error, isNotNull);
  });
}
