import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderCard extends ConsumerWidget {
  final Map<String, dynamic> order;

  const OrderCard({super.key, required this.order});

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? "0") ?? 0;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  int _quantity(Map<String, dynamic> item) {
    return _asInt(item["quantity"] ?? item["qty"], fallback: 1);
  }

  double _price(Map<String, dynamic> item) {
    return _asDouble(item["price"]);
  }

  double _lineTotal(Map<String, dynamic> item) {
    final total = _asDouble(item["total"]);
    if (total > 0) return total;
    return _quantity(item) * _price(item);
  }

  double _calculateAmount(List items) {
    return items.fold<double>(0, (sum, item) {
      return sum + _lineTotal(Map<String, dynamic>.from(item));
    });
  }

  double _fallbackOrderAmount(Map<String, dynamic> order) {
    return _asDouble(
      order["total_amount"] ??
          order["amount"] ??
          order["total"] ??
          order["price"],
    );
  }

  String _productName(Map<String, dynamic> item) {
    return (item["product_name"] ?? item["product"] ?? item["name"] ?? "Item")
        .toString();
  }

  String _currency(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _call(BuildContext context, String phone, String name) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number not available")),
      );
      return;
    }

    final url = Uri.parse("tel:$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Calling $name")));
    }
  }

  Future<void> _whatsapp(
    BuildContext context,
    String phone,
    String name,
  ) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("WhatsApp number not available")),
      );
      return;
    }

    final url = Uri.parse("https://wa.me/$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Opening WhatsApp for $name")));
    }
  }

  bool _isHotLead(Map<String, dynamic> lead) {
    final msg = (lead["msg"] ?? "").toString().toLowerCase();
    final intent = (lead["intent"] ?? "").toString().toLowerCase();

    return intent == "high" ||
        msg.contains("price") ||
        msg.contains("buy") ||
        msg.contains("order") ||
        msg.contains("cost");
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month} "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _updateStatus(
    BuildContext context,
    LeadsController controller,
    Map<String, dynamic> order,
    String nextStatus,
    String message,
  ) async {
    await controller.updateOrderStatus(order, nextStatus);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(leadsControllerProvider.notifier);
    final leads = ref.watch(leadsControllerProvider);

    final liveOrder = leads.firstWhere(
      (l) => l["id"] == order["id"],
      orElse: () => order,
    );

    final items = (liveOrder["items"] ?? []) as List;
    final phone = (liveOrder["phone"] ?? "").toString();
    final name = (liveOrder["name"] ?? "Customer").toString();
    final status = (liveOrder["order_status"] ?? "pending").toString();

    final created = _parseDate(liveOrder["created_at"]);
    final completed = _parseDate(liveOrder["completed_at"]);
    final computedAmount = _calculateAmount(items);
    final amount = computedAmount > 0
        ? computedAmount
        : _fallbackOrderAmount(liveOrder);
    final isHot = _isHotLead(liveOrder);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isHot ? const Color(0xFFF4D7BF) : const Color(0xFFEDEFF5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: (isHot ? const Color(0xFFB85C00) : Colors.black)
                  .withValues(alpha: isHot ? 0.08 : 0.03),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Created ${_formatDate(created)}",
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isHot)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4EA),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFF4D7BF)),
                    ),
                    child: const Text(
                      "🔥 Hot",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB85C00),
                      ),
                    ),
                  ),
                _statusBadge(status),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Order Total",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "₹${_currency(amount)}",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      "${items.length} items",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (items.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.take(3).map<Widget>((item) {
                  final orderItem = Map<String, dynamic>.from(item);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${_quantity(orderItem)} x ${_productName(orderItem)}",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (status == "completed" && completed != null) ...[
              const SizedBox(height: 10),
              Text(
                "Completed ${_formatDate(completed)}",
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF0F9D58),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _btn(
                    FontAwesomeIcons.whatsapp,
                    "Chat",
                    const Color(0xFF25D366),
                    () => _whatsapp(context, phone, name),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(
                    FontAwesomeIcons.phone,
                    "Call",
                    const Color(0xFF6C4ED9),
                    () => _call(context, phone, name),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(
                    status == "pending"
                        ? FontAwesomeIcons.play
                        : FontAwesomeIcons.check,
                    status == "pending"
                        ? "Start Order"
                        : status == "processing"
                        ? "Done"
                        : "Done",
                    status == "completed"
                        ? const Color(0xFF9CA3AF)
                        : status == "pending"
                        ? const Color(0xFFE08B00)
                        : const Color(0xFF0F9D58),
                    status == "completed"
                        ? null
                        : () {
                            if (status == "pending") {
                              _updateStatus(
                                context,
                                controller,
                                liveOrder,
                                "processing",
                                "Order started",
                              );
                            } else if (status == "processing") {
                              _updateStatus(
                                context,
                                controller,
                                liveOrder,
                                "completed",
                                "Order marked complete",
                              );
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

  Widget _btn(IconData icon, String text, Color color, VoidCallback? onTap) {
    final isEnabled = onTap != null;

    return Opacity(
      opacity: isEnabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 35,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case "processing":
        color = const Color(0xFF2563EB);
        label = "In Progress";
        break;
      case "completed":
        color = const Color(0xFF0F9D58);
        label = "Completed";
        break;
      default:
        color = const Color(0xFFE08B00);
        label = "Pending";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
