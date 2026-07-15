import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_stats.dart';

abstract class CustomerStatsService {
  Future<CustomerStats?> fetchStats(String customerId);
}

class SupabaseCustomerStatsService implements CustomerStatsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<CustomerStats?> fetchStats(String customerId) async {
    final results = await Future.wait([
      _client
          .from('customer_stats')
          .select('customer_id, total_orders, lifetime_value, outstanding')
          .eq('customer_id', customerId)
          .eq('user_id', _userId)
          .maybeSingle(),
      _client
          .from('customers')
          .select('id, name, phone, ai_facts, birthday, last_contact_at')
          .eq('id', customerId)
          .eq('user_id', _userId)
          .maybeSingle(),
    ]);

    final statsRow = results[0];
    final customerRow = results[1];

    if (customerRow == null) return null;

    return CustomerStats.fromMaps(
      statsMap: statsRow ?? {'customer_id': customerId},
      customerMap: customerRow,
    );
  }
}
