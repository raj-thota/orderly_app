import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

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

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month}/${d.year}";
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month}/${d.year} • "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
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
      (l) => l["id"].toString() == order["id"].toString(),
      orElse: () => order,
    );

    final items = (liveOrder["items"] ?? []) as List;
    final phone = (liveOrder["phone"] ?? "").toString();
    final name = (liveOrder["name"] ?? "Customer").toString();
    final status = (liveOrder["order_status"] ?? "pending").toString();

    final createdAt = _parseDate(liveOrder["created_at"]);
    final completedAt = _parseDate(liveOrder["completed_at"]);
    final amount = _calculateAmount(items);
    final subtotal = amount;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("Order Detail"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7FF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : "C",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6C4ED9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            createdAt != null
                                ? "Created ${_formatDateTime(createdAt)}"
                                : "Order timeline unavailable",
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _heroStat(
                        "Order Total",
                        "₹${_currency(amount)}",
                        const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _heroStat(
                        "Items",
                        items.length.toString(),
                        const Color(0xFF6C4ED9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _smallActionButton(
                "WhatsApp",
                FontAwesomeIcons.whatsapp,
                const Color(0xFF25D366),
                () => _whatsapp(context, phone, name),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                "Call",
                FontAwesomeIcons.phone,
                const Color(0xFF6C4ED9),
                () => _call(context, phone, name),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                status == "completed" ? "Done" : "Done",
                status == "pending"
                    ? FontAwesomeIcons.play
                    : FontAwesomeIcons.check,
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
                            "Order moved to processing",
                          );
                        } else {
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
            ],
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Items",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Text(
                    "No items added yet",
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ...items.map<Widget>((item) {
                  final orderItem = Map<String, dynamic>.from(item);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE7FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                _quantity(orderItem).toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF6C4ED9),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _productName(orderItem),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "₹${_currency(_price(orderItem))} each",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "₹${_currency(_lineTotal(orderItem))}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _summaryRow("Subtotal", "₹${_currency(subtotal)}"),
                  _summaryRow("Items", items.length.toString()),
                  _summaryRow(
                    "Status",
                    status == "processing"
                        ? "In Progress"
                        : status == "completed"
                        ? "Completed"
                        : "Pending",
                  ),
                  const SizedBox(height: 8),
                  _summaryRow("Total", "₹${_currency(amount)}", isTotal: true),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Timeline",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                _timelineItem(
                  "Order Created",
                  true,
                  _formatDateTime(createdAt),
                ),
                _timelineItem(
                  "Processing",
                  status == "processing" || status == "completed",
                  status == "pending"
                      ? "Waiting to start"
                      : "Order is being processed",
                ),
                _timelineItem(
                  "Completed",
                  status == "completed",
                  status == "completed"
                      ? _formatDateTime(completedAt)
                      : "Not completed yet",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6DDFE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C4ED9).withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _heroStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    final isEnabled = onTap != null;

    return Expanded(
      child: Opacity(
        opacity: isEnabled ? 1 : 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 35,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
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
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: isTotal
                  ? const Color(0xFF111827)
                  : const Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineItem(String title, bool active, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF0F9D58).withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.check_rounded : Icons.circle_outlined,
              color: active ? const Color(0xFF0F9D58) : const Color(0xFF9CA3AF),
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
