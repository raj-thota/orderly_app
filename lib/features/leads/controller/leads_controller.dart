import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/notification_service.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Legacy-shaped state for pre-spec screens (Dashboard, Orders, notifications).
/// Backed by the enquiries data layer; retired when stages 4/7 rebuild them.
final leadsControllerProvider =
    StateNotifierProvider<LeadsController, List<Map<String, dynamic>>>((ref) {
      return LeadsController(EnquiriesService());
    });

class LeadsController extends StateNotifier<List<Map<String, dynamic>>> {
  LeadsController(this._service) : super([]);

  final EnquiriesService _service;
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> loadLeads() async {
    try {
      state = await _service.fetchLegacyMaps();
      await NotificationService.syncLeadNotifications(leads: state);
    } catch (_) {
      // Keep previous state on failure; surviving legacy screens have no
      // error surface. New screens handle errors properly.
    }
  }

  /// Notifications screen "mark done": converts the enquiry to an order.
  Future<void> markDone(Map<String, dynamic> lead) async {
    try {
      final customerId = lead['customer_id']?.toString();
      if (customerId == null) return;
      await _service.createOrder(
        customerId: customerId,
        leadId: lead['id'].toString(),
        items: const [DraftItem(name: 'Item', qty: 1)],
      );
      await loadLeads();
    } catch (_) {}
  }

  /// Order detail status stepper. Legacy statuses map onto the new enum.
  Future<void> updateOrderStatus(
    Map<String, dynamic> order,
    String status,
  ) async {
    const map = {
      'pending': 'pending',
      'processing': 'packed',
      'completed': 'delivered',
      'packed': 'packed',
      'shipped': 'shipped',
      'delivered': 'delivered',
    };
    final orderId = (order['order_id'] ?? order['id'])?.toString();
    final mapped = map[status];
    if (orderId == null || mapped == null) return;
    try {
      await _client
          .from('orders')
          .update({
            'status': mapped,
            if (mapped == 'delivered')
              'delivered_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      await loadLeads();
    } catch (_) {}
  }

  /// Order detail item editor, re-pointed at real order_items.
  Future<void> updateOrderItems(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
  ) async {
    final orderId = (order['order_id'] ?? order['id'])?.toString();
    final userId = _client.auth.currentUser?.id;
    if (orderId == null || userId == null) return;

    await _client.from('order_items').delete().eq('order_id', orderId);
    double subtotal = 0;
    final rows = items.map((item) {
      final qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
      final price = double.tryParse(item['price']?.toString() ?? '') ?? 0;
      subtotal += price * qty;
      return {
        'user_id': userId,
        'order_id': orderId,
        'name': (item['product_name'] ?? item['name'] ?? 'Item').toString(),
        'unit_price': price,
        'qty': qty,
        'line_total': price * qty,
      };
    }).toList();
    if (rows.isNotEmpty) {
      await _client.from('order_items').insert(rows);
    }
    await _client
        .from('orders')
        .update({'subtotal': subtotal, 'grand_total': subtotal})
        .eq('id', orderId);
    await loadLeads();
  }
}
