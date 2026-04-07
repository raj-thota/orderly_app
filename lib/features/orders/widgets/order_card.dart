import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';

class OrderCard extends ConsumerWidget {
  final Map<String, dynamic> order;

  const OrderCard({super.key, required this.order});

  /// 📞 CALL
  Future<void> _call(BuildContext context, String phone, String name) async {
    final url = Uri.parse("tel:$phone");
    await launchUrl(url);
  }

  /// 💬 WHATSAPP
  Future<void> _whatsapp(
      BuildContext context, String phone, String name) async {
    final url = Uri.parse("https://wa.me/$phone");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// 💰 CALCULATE AMOUNT (REAL)
  int _calculateAmount(List items) {
    return items.fold<int>(0, (sum, i) {
      final qty = int.tryParse(i["quantity"]?.toString() ?? "1") ?? 1;
      final price = int.tryParse(i["price"]?.toString() ?? "0") ?? 0;
      return sum + (qty * price);
    });
  }

  /// 🔥 HOT DETECTION
  bool _isHotLead(Map<String, dynamic> lead) {
    final msg = (lead["msg"] ?? "").toString().toLowerCase();
    final intent = (lead["intent"] ?? "").toString().toLowerCase();

    return intent == "high" ||
        msg.contains("price") ||
        msg.contains("buy") ||
        msg.contains("order") ||
        msg.contains("cost");
  }

  /// 📅 SAFE DATE PARSER
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// 🕒 FORMAT DATE (POLISHED)
  String _formatDate(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month} "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(leadsControllerProvider.notifier);
    final leads = ref.watch(leadsControllerProvider);

    /// 🔥 LIVE DATA SYNC
    final liveOrder = leads.firstWhere(
      (l) => l["id"] == order["id"],
      orElse: () => order,
    );

    final items = (liveOrder["items"] ?? []) as List;
    final phone = liveOrder["phone"] ?? "";
    final name = liveOrder["name"] ?? "";
    final status = liveOrder["order_status"] ?? "pending";

    final created = _parseDate(liveOrder["created_at"]);
    final completed = _parseDate(liveOrder["completed_at"]);

    final amount = _calculateAmount(items);
    final isHot = _isHotLead(liveOrder);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(order: liveOrder),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔥 HEADER
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),

                if (isHot)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "🔥 Hot",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ),

                _statusBadge(status),
              ],
            ),

            const SizedBox(height: 6),

            /// 🕒 META
            Row(
              children: [
                Text(
                  "Created: ${_formatDate(created)}",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                if (status == "completed")
                  Text(
                    "Done: ${_formatDate(completed)}",
                    style: const TextStyle(fontSize: 11, color: Colors.green),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            /// 🧾 ITEMS
            if (items.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items.map<Widget>((item) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${item["quantity"]} x ${item["product_name"] ?? item["product"] ?? ""}",
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 10),

            /// 💰 AMOUNT
            Row(
              children: [
                Text(
                  "₹$amount",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${items.length} items",
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// 🔘 ACTIONS (PREMIUM)
            Row(
              children: [
                Expanded(
                  child: _btn(Icons.chat, "Chat", Colors.green,
                      () => _whatsapp(context, phone, name)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(Icons.call, "Call", Colors.deepPurple,
                      () => _call(context, phone, name)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(
                    status == "pending" ? Icons.play_arrow : Icons.check,
                    status == "pending"
                        ? "Start"
                        : status == "processing"
                            ? "Done"
                            : "Done",
                    status == "completed"
                        ? Colors.grey
                        : status == "pending"
                            ? Colors.orange
                            : Colors.green,
                    () {
                      if (status == "pending") {
                        controller.updateOrderStatus(liveOrder, "processing");
                      } else if (status == "processing") {
                        controller.updateOrderStatus(liveOrder, "completed");
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 🔘 PREMIUM BUTTON
  Widget _btn(
      IconData icon, String text, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🟢 STATUS BADGE
  Widget _statusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case "processing":
        color = Colors.blue;
        label = "In Progress";
        break;
      case "completed":
        color = Colors.green;
        label = "Completed";
        break;
      default:
        color = Colors.orange;
        label = "Pending";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}