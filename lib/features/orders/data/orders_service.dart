import 'package:supabase_flutter/supabase_flutter.dart';

import 'order.dart';

const _selectWithJoins = '*, customers(name, phone), order_items(*)';

class OrdersService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<Order>> fetchOrders() async {
    final rows = await _client
        .from('orders')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return rows.map<Order>((r) => Order.fromMap(r)).toList();
  }

  Future<Order?> fetchById(String id) async {
    final row = await _client
        .from('orders')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Order.fromMap(row);
  }

  Future<void> updateOrder(String id, Map<String, dynamic> changes) async {
    await _client
        .from('orders')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> markDelivered(String id) async {
    await _client.rpc('mark_order_delivered', params: {'p_order_id': id});
  }
}
