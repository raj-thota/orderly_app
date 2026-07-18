import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_order_draft.dart';
import 'order.dart';

const _selectWithJoins = '*, customers(name, phone), order_items(*), payments(*)';

/// Serializes draft items into the jsonb `p_items` array the create-order RPC
/// consumes. `item_type` + `image_url` are snapshotted for badge display.
List<Map<String, dynamic>> buildItemsPayload(List<CreateOrderItem> items) {
  return items
      .map((i) => {
            'name': i.name,
            'qty': i.qty,
            'unit_price': i.unitPrice,
            'item_type': i.type,
            if (i.productId != null) 'product_id': i.productId,
            if (i.imageUrl != null) 'image_url': i.imageUrl,
          })
      .toList();
}

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

  Future<void> cancelOrder(String id) async {
    await _client.rpc('cancel_order', params: {'p_order_id': id});
  }

  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<CreateOrderItem> items,
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
    String? notes,
  }) async {
    final payload = buildItemsPayload(items);
    final orderId = await _client.rpc('create_order_with_items', params: {
      'p_customer_id': customerId,
      'p_lead_id': leadId,
      'p_items': payload,
      'p_discount': discount,
      'p_shipping_fee': shippingFee,
      'p_expected_date': expectedDate?.toIso8601String().substring(0, 10),
      'p_notes': notes,
    });
    return orderId.toString();
  }
}
