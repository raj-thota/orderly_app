import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

  Future<void> _call(BuildContext context, String phone, String name) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("📞 Calling $name...")));

    final url = Uri.parse("tel:$phone");
    await launchUrl(url);
  }

  Future<void> _whatsapp(
    BuildContext context,
    String phone,
    String name,
  ) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("💬 Opening WhatsApp for $name")));

    final url = Uri.parse("https://wa.me/$phone");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  int _calculateAmount(List items) {
    return items.fold<int>(0, (sum, i) {
      final qty = int.tryParse(i["quantity"]?.toString() ?? "1") ?? 1;
      final price = int.tryParse(i["price"]?.toString() ?? "0") ?? 0;
      return sum + (qty * price);
    });
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(leadsControllerProvider.notifier);
    final leads = ref.watch(leadsControllerProvider);

    /// 🔥 ALWAYS USE LIVE DATA
    final liveOrder = leads.firstWhere(
      (l) => l["id"].toString() == order["id"].toString(),
      orElse: () => order,
    );

    final items = liveOrder["items"] ?? [];
    final phone = liveOrder["phone"] ?? "";
    final name = liveOrder["name"] ?? "";
    final status = liveOrder["order_status"] ?? "pending";

    final createdAt = _parseDate(liveOrder["created_at"]);
    final amount = _calculateAmount(items);

    return Scaffold(
      appBar: AppBar(title: const Text("Order Details")),
      backgroundColor: Colors.grey.shade50,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(name, status, createdAt),
          const SizedBox(height: 18),
          _itemsCard(items, amount),
          const SizedBox(height: 16),
          _timeline(status),
          const SizedBox(height: 20),
          _actions(context, controller, liveOrder, phone, name, status),
        ],
      ),
    );
  }

  Widget _header(String name, String status, DateTime? createdAt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.deepPurple.shade50,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : "C",
                  style: const TextStyle(color: Colors.deepPurple),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          if (createdAt != null)
            Text(
              "Created: ${createdAt.day}/${createdAt.month} ${createdAt.hour}:${createdAt.minute}",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(List items, int amount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Items", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          if (items.isEmpty)
            const Text("No items", style: TextStyle(color: Colors.grey)),

          ...items.map<Widget>((i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${i["quantity"]} x ${i["product"]}"),
                  Text("₹${i["price"] ?? 0}"),
                ],
              ),
            );
          }),

          const Divider(),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "₹$amount",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeline(String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Timeline", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _timelineItem("Order Created", true),
          _timelineItem(
            "Processing",
            status == "processing" || status == "completed",
          ),
          _timelineItem("Completed", status == "completed"),
        ],
      ),
    );
  }

  Widget _timelineItem(String title, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            color: active ? Colors.green : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    LeadsController controller,
    Map<String, dynamic> order,
    String phone,
    String name,
    String status,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _btn(
                "WhatsApp",
                Icons.chat,
                const Color(0xFF25D366),
                () => _whatsapp(context, phone, name),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _btn(
                "Call",
                Icons.phone,
                Colors.deepPurple,
                () => _call(context, phone, name),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (status == "pending")
          _btn("Start Order", Icons.play_arrow, Colors.orange, () {
            controller.updateOrderStatus(order, "processing");
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Order started 🚀")));
          }),
        if (status == "processing")
          _btn("Mark as Done", Icons.check, Colors.green, () {
            controller.updateOrderStatus(order, "completed");
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Order completed ✅")));
          }),
      ],
    );
  }

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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
      ],
    );
  }

  Widget _btn(String text, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
