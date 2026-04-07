import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/leads_service.dart';

final leadsControllerProvider =
    StateNotifierProvider<LeadsController, List<Map<String, dynamic>>>((ref) {
  return LeadsController();
});

class LeadsController extends StateNotifier<List<Map<String, dynamic>>> {
  final _service = LeadsService();

  LeadsController() : super([]);

  Future<void> loadLeads() async {
    try {
      final data = await _service.fetchLeads();
      state = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      // Error loading leads
    }
  }

Future<void> addLead(
  Map<String, dynamic> lead,
  List<Map<String, dynamic>> items,
) async {
  try {
    final leadId = await _service.addLead(lead);

    /// 🔥 SAVE ITEMS
    if (items.isNotEmpty) {
      await _service.addOrderItems(leadId, items);
    }

    await loadLeads();
  } catch (e) {
    rethrow;
  }
}

  Future<void> editLead(
    Map<String, dynamic> lead,
    Map<String, dynamic> updatedData,
  ) async {
    try {
      await _service.updateLead(lead["id"], updatedData);
      await loadLeads();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteLead(Map<String, dynamic> lead) async {
    try {
      await _service.deleteLead(lead["id"]);
      await loadLeads();
    } catch (e) {
      // Error deleting lead
    }
  }

  Future<void> markDone(Map<String, dynamic> lead) async {
    try {
      await _service.updateLead(lead["id"], {
        "status": "closed",
        "order_status": "pending",
        "completed_at": DateTime.now().toIso8601String(),
      });
      await loadLeads();
    } catch (e) {
      // Error marking lead as done
    }
  }

  Future<void> restoreLead(int index, Map<String, dynamic> lead) async {
    try {
      await _service.addLead(lead);
      await loadLeads();
    } catch (e) {
      // Error restoring lead
    }
  }

  Future<void> updateOrderStatus(
    Map<String, dynamic> lead,
    String status,
  ) async {
    try {
      await _service.updateLead(lead["id"], {
        "order_status": status,
        if (status == "completed")
          "completed_at": DateTime.now().toIso8601String(),
      });
      await loadLeads();
    } catch (e) {
      // Error updating order status
    }
  }

  Future<void> followUp(
    Map<String, dynamic> lead,
    String note,
    DateTime date,
  ) async {
    try {
      await _service.updateLead(lead["id"], {
        "status": "follow",
        "follow_up_note": note,
        "follow_up_date": date.toIso8601String(),
      });
      await loadLeads();
    } catch (e) {
      // Error setting follow up
    }
  }
  
}