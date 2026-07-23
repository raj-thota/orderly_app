import 'package:supabase_flutter/supabase_flutter.dart';

abstract class CheckoutService {
  /// [plan] is the tier key (currently only 'pro_monthly'); the price itself
  /// is resolved server-side, never sent from the client.
  Future<Uri> createCheckout({required String gateway, required String plan});
}

class SupabaseCheckoutService implements CheckoutService {
  SupabaseClient get _client => Supabase.instance.client;

  // Server error keys mapped to copy a seller can act on. The raw key must
  // never reach the screen.
  static const _friendlyErrors = {
    'already_subscribed':
        "You're already subscribed — no new payment is needed.",
    'plan_change_failed':
        'Could not switch your plan. Please try again or contact support.',
  };

  @override
  Future<Uri> createCheckout({
    required String gateway,
    required String plan,
  }) async {
    final res = await _client.functions.invoke(
      'create-checkout',
      body: {'gateway': gateway, 'plan': plan},
    );
    if (res.data == null) throw Exception('checkout_empty_response');
    final data = res.data as Map<String, dynamic>;
    final errorKey = data['error']?.toString();
    if (errorKey != null) {
      throw Exception(
        _friendlyErrors[errorKey] ??
            'Could not start checkout. Please try again.',
      );
    }

    // Razorpay returns short_url; Stripe returns checkout_url.
    final url =
        data['checkout_url']?.toString() ?? data['short_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('checkout_no_url');
    return Uri.parse(url);
  }
}
