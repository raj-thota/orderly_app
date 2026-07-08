import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/notification_service.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';

/// Legacy-shaped state for pre-spec screens (Dashboard, Orders, notifications).
/// Backed by the enquiries data layer; retired when stages 4/7 rebuild them.
final leadsControllerProvider =
    StateNotifierProvider<LeadsController, List<Map<String, dynamic>>>((ref) {
      return LeadsController(EnquiriesService());
    });

class LeadsController extends StateNotifier<List<Map<String, dynamic>>> {
  LeadsController(this._service) : super([]);

  final EnquiriesService _service;

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
}
