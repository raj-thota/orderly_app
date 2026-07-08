import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer.dart';

class CustomersService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// Links to the existing customer with this phone, else creates one.
  /// Phone-less customers are always created fresh (mergeable later).
  Future<Customer> createOrLink({required String name, String? phone}) async {
    final cleanPhone = (phone ?? '').trim().isEmpty ? null : phone!.trim();

    if (cleanPhone != null) {
      final existing = await _client
          .from('customers')
          .select()
          .eq('user_id', _userId)
          .eq('phone', cleanPhone)
          .maybeSingle();
      if (existing != null) return Customer.fromMap(existing);
    }

    final row = await _client
        .from('customers')
        .insert({
          'user_id': _userId,
          'name': name.trim().isEmpty ? 'Customer' : name.trim(),
          'phone': ?cleanPhone,
        })
        .select()
        .single();
    return Customer.fromMap(row);
  }
}
