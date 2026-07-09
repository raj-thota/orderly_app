import 'package:supabase_flutter/supabase_flutter.dart';

class InvoiceService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> assignInvoiceNumber(String orderId) async {
    final res = await _client
        .rpc('assign_invoice_number', params: {'p_order_id': orderId});
    return res.toString();
  }
}
