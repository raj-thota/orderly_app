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

    return response.map((lead) => _normalizeLead(lead)).toList();
  }

  Future<Map<String, dynamic>?> fetchLeadById(String id) async {
    final user = supabase.auth.currentUser;

    if (user == null) return null;

    final response = await supabase
        .from('leads')
        .select('*, order_items(*)')
        .eq('user_id', user.id)
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;

    return _normalizeLead(response);
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
          "activities": [
            {
              "type": "created",
              "note": "Lead added",
              "time": DateTime.now().toIso8601String(),
            },
          ],
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
    final formatted = _formatOrderItems(leadId, items);

    if (formatted.isEmpty) return;

    await supabase.from("order_items").insert(formatted);
  }

  Future<void> replaceOrderItems(
    String leadId,
    List<Map<String, dynamic>> items,
  ) async {
    await supabase.from("order_items").delete().eq("lead_id", leadId);

    final formatted = _formatOrderItems(leadId, items);
    if (formatted.isEmpty) return;

    await supabase.from("order_items").insert(formatted);
  }

  Future<void> appendLeadActivity(
    String leadId,
    Map<String, dynamic> activity,
  ) async {
    final existing = await supabase
        .from('leads')
        .select(
          'activities, created_at, follow_up_date, follow_up_note, status, completed_at',
        )
        .eq('id', leadId)
        .maybeSingle();

    if (existing == null) return;

    final normalized = _normalizeActivities(existing);
    normalized.add({
      "type": activity["type"] ?? "activity",
      "note": activity["note"],
      "time": (activity["time"] ?? DateTime.now().toIso8601String()).toString(),
    });

    await supabase
        .from('leads')
        .update({
          "activities": normalized,
          "updated_at": DateTime.now().toIso8601String(),
        })
        .eq('id', leadId);
  }

  Map<String, dynamic> _normalizeLead(Map<String, dynamic> lead) {
    return {
      ...lead,
      "items": lead["order_items"] ?? [],
      "activities": _normalizeActivities(lead),
    };
  }

  List<Map<String, dynamic>> _normalizeActivities(Map<String, dynamic> lead) {
    final normalized = <Map<String, dynamic>>[];
    final rawActivities = lead["activities"];

    if (rawActivities is List) {
      for (final activity in rawActivities) {
        if (activity is! Map) continue;

        final map = Map<String, dynamic>.from(activity);
        final parsedTime = _parseDateTime(map["time"]);
        normalized.add({
          "type": (map["type"] ?? "activity").toString(),
          "note": map["note"]?.toString(),
          "time": (parsedTime ?? DateTime.now()).toIso8601String(),
        });
      }
    }

    void addFallback({
      required String type,
      required dynamic time,
      String? note,
      bool Function(Map<String, dynamic>)? whenExists,
    }) {
      final parsedTime = _parseDateTime(time);
      if (parsedTime == null) return;

      final exists = normalized.any(
        (activity) =>
            activity["type"] == type && (whenExists?.call(activity) ?? true),
      );
      if (exists) return;

      normalized.add({
        "type": type,
        "note": note,
        "time": parsedTime.toIso8601String(),
      });
    }

    addFallback(type: "created", time: lead["created_at"], note: "Lead added");
    addFallback(
      type: "follow_up",
      time: lead["follow_up_date"],
      note: lead["follow_up_note"]?.toString() ?? "Follow-up scheduled",
    );
    addFallback(
      type: "done",
      time: lead["completed_at"],
      note: (lead["status"] ?? "").toString().toLowerCase() == "closed"
          ? "Converted to order"
          : "Marked done",
    );

    normalized.sort((a, b) {
      final second =
          _parseDateTime(b["time"]) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final first =
          _parseDateTime(a["time"]) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return second.compareTo(first);
    });

    return normalized;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  List<Map<String, dynamic>> _formatOrderItems(
    String leadId,
    List<Map<String, dynamic>> items,
  ) {
    return items.map((item) {
      final quantity = _asInt(item["quantity"] ?? item["qty"], fallback: 1);
      final price = _asDouble(item["price"]);

      return {
        "lead_id": leadId,
        "product_name":
            (item["product_name"] ?? item["product"] ?? item["name"] ?? "Item")
                .toString(),
        "quantity": quantity,
        "price": price,
        "total": _asDouble(item["total"]) > 0
            ? _asDouble(item["total"])
            : quantity * price,
        "created_at": DateTime.now().toIso8601String(),
      };
    }).toList();
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? "0") ?? 0;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }
}
