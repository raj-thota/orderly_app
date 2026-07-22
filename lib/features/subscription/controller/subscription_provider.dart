import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/checkout_service.dart';
import '../data/subscription.dart';
import '../data/subscription_service.dart';

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (_) => SupabaseSubscriptionService(),
);

final checkoutServiceProvider = Provider<CheckoutService>(
  (_) => SupabaseCheckoutService(),
);

/// Realtime stream of the user's subscription row (null = no row yet).
/// Also calls ensureTrial() on init so a trial row is created on first load.
final subscriptionProvider = StreamProvider.autoDispose<Subscription?>((
  ref,
) async* {
  final svc = ref.watch(subscriptionServiceProvider);
  await svc.ensureTrial();
  yield* svc.watchSubscription();
});

/// Derives the entitlement from the subscription stream.
/// Defaults to gated while loading or if no subscription exists.
final entitlementProvider = Provider.autoDispose<EntitlementStatus>((ref) {
  final async = ref.watch(subscriptionProvider);
  return async.valueOrNull?.entitlement ?? EntitlementStatus.gated;
});

// ---------------------------------------------------------------------------
// Checkout controller
// ---------------------------------------------------------------------------

class CheckoutState {
  const CheckoutState({this.loading = false, this.error});
  final bool loading;
  final String? error;

  CheckoutState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
  }) => CheckoutState(
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier(this._service) : super(const CheckoutState());

  final CheckoutService _service;

  Future<Uri?> startCheckout({
    required String gateway,
    required String plan,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final uri = await _service.createCheckout(gateway: gateway, plan: plan);
      state = state.copyWith(loading: false);
      return uri;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return null;
    }
  }
}

final checkoutControllerProvider =
    StateNotifierProvider.autoDispose<CheckoutNotifier, CheckoutState>((ref) {
      return CheckoutNotifier(ref.watch(checkoutServiceProvider));
    });
