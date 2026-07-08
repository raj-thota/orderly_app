import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> recordPayment(
    String orderId,
    double amount,
    String method,
  ) async {
    await _client.rpc('record_payment', params: {
      'p_order_id': orderId,
      'p_amount': amount,
      'p_method': method,
    });
  }
}
