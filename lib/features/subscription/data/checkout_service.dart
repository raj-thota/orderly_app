import 'package:supabase_flutter/supabase_flutter.dart';

abstract class CheckoutService {
  /// [plan] is the tier key ('starter_monthly' | 'pro_monthly'); the price
  /// itself is resolved server-side, never sent from the client.
  Future<Uri> createCheckout({required String gateway, required String plan});
}

class SupabaseCheckoutService implements CheckoutService {
  SupabaseClient get _client => Supabase.instance.client;

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
    if (data['error'] != null) throw Exception(data['error']);

    // Razorpay returns short_url; Stripe returns checkout_url.
    final url =
        data['checkout_url']?.toString() ?? data['short_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('checkout_no_url');
    return Uri.parse(url);
  }
}
