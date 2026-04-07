import 'package:supabase_flutter/supabase_flutter.dart';

class LeadsService {
  final supabase = Supabase.instance.client;

  /// 📥 GET
  Future<List<Map<String, dynamic>>> fetchLeads() async {
    final user = supabase.auth.currentUser;

    // final userId = user?.id ?? "9107e05c-ce5d-48a0-9d40-8b4c9c76d851";
    if (user == null) return [];

    final response = await supabase
        .from('leads')
        .select('*, order_items(*)') // 🔥 JOIN
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return response.map((l) {
      return {...l, "items": l["order_items"] ?? []};
    }).toList();
  }

  /// ➕ ADD
  Future<String> addLead(Map<String, dynamic> lead) async {
    final user = supabase.auth.currentUser;

    // final userId = user?.id ?? "9107e05c-ce5d-48a0-9d40-8b4c9c76d851";

    if (user == null) throw Exception("User not logged in");

    final response = await supabase
        .from('leads')
        .insert({
          ...lead,
          "user_id": user.id,
          "created_at": DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return response["id"]; // 🔥 IMPORTANT
  }

  /// ✏️ UPDATE
  Future<void> updateLead(String id, Map<String, dynamic> data) async {
    await supabase
        .from('leads')
        .update({...data, "updated_at": DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  /// ❌ DELETE
  Future<void> deleteLead(String id) async {
    await supabase.from('leads').delete().eq('id', id);
  }

  Future<void> addOrderItems(
    String leadId,
    List<Map<String, dynamic>> items,
  ) async {
    final formatted = items.map((i) {
      return {
        "lead_id": leadId,
        "product_name": i["name"],
        "quantity": i["qty"],
        "price": i["price"],
        "total": (i["qty"] ?? 1) * (i["price"] ?? 0),
        "created_at": DateTime.now().toIso8601String(),
      };
    }).toList();

    await supabase.from("order_items").insert(formatted);
  }
}
