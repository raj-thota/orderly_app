import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';

final ordersControllerProvider =
    Provider<List<Map<String, dynamic>>>((ref) {
  final leads = ref.watch(leadsControllerProvider);

  return leads
      .where((l) => l["status"] == "closed")
      .map((l) {
        return {
          ...l,
          "order_status": l["order_status"] ?? "pending",
          "items": l["items"] ?? [], // 🔥 important
        };
      })
      .toList();
});