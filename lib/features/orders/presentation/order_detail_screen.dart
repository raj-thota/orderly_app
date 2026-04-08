import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/main.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  List<Map<String, dynamic>> _draftItems = <Map<String, dynamic>>[];
  String _sourceItemsSignature = '';
  bool _hasPendingLocalEdits = false;
  bool _isSavingItems = false;

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

  double _fallbackOrderAmount(Map<String, dynamic> order) {
    return _asDouble(
      order["total_amount"] ??
          order["amount"] ??
          order["total"] ??
          order["price"],
    );
  }

  double _calculateAmount(Map<String, dynamic> order, List items) {
    final computed = items.fold<double>(0, (sum, item) {
      return sum + _lineTotal(Map<String, dynamic>.from(item));
    });

    if (computed > 0) return computed;
    return _fallbackOrderAmount(order);
  }

  int _totalUnits(List items) {
    return items.fold<int>(0, (sum, item) {
      return sum + _quantity(Map<String, dynamic>.from(item));
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

  String _formatDateTime(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month}/${d.year} • "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  List<Map<String, dynamic>> _normalizeItems(List items) {
    return items.map((item) {
      final map = Map<String, dynamic>.from(item);
      final quantity = _quantity(map);
      final price = _price(map);

      return {
        "product_name": _productName(map),
        "quantity": quantity,
        "price": price,
        "total": _lineTotal({
          "quantity": quantity,
          "price": price,
          "total": map["total"],
        }),
      };
    }).toList();
  }

  String _itemsSignature(List<Map<String, dynamic>> items) {
    return items
        .map(
          (item) =>
              "${_productName(item)}|${_quantity(item)}|${_price(item)}|${_lineTotal(item)}",
        )
        .join(",");
  }

  void _syncDraftItems(List sourceItems) {
    final normalized = _normalizeItems(sourceItems);
    final signature = _itemsSignature(normalized);
    if (_hasPendingLocalEdits || signature == _sourceItemsSignature) return;

    _draftItems = normalized;
    _sourceItemsSignature = signature;
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _call(String phone, String name) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      _showSnackBar("Phone number not available");
      return;
    }

    final url = Uri.parse("tel:$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
      _showSnackBar("Calling $name");
    }
  }

  Future<void> _whatsapp(String phone, String name) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      _showSnackBar("WhatsApp number not available");
      return;
    }

    final url = Uri.parse("https://wa.me/$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      _showSnackBar("Opening WhatsApp for $name");
    }
  }

  Future<void> _updateStatus(
    LeadsController controller,
    Map<String, dynamic> order,
    String nextStatus,
    String message,
  ) async {
    await controller.updateOrderStatus(order, nextStatus);
    _showSnackBar(message);
  }

  Future<void> _openItemEditor({
    Map<String, dynamic>? existingItem,
    int? index,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OrderItemEditorSheet(item: existingItem),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (index == null) {
        _draftItems = [..._draftItems, result];
      } else {
        final updated = [..._draftItems];
        updated[index] = result;
        _draftItems = updated;
      }
      _hasPendingLocalEdits = true;
    });

    _showSnackBar(index == null ? "Item added" : "Item updated");
  }

  void _removeItem(int index) {
    final removedName = _productName(_draftItems[index]);

    setState(() {
      final updated = [..._draftItems]..removeAt(index);
      _draftItems = updated;
      _hasPendingLocalEdits = true;
    });

    _showSnackBar("$removedName removed");
  }

  Future<void> _saveItems(
    LeadsController controller,
    Map<String, dynamic> liveOrder,
  ) async {
    setState(() {
      _isSavingItems = true;
    });

    try {
      await controller.updateOrderItems(liveOrder, _draftItems);
      if (!mounted) return;
      setState(() {
        _isSavingItems = false;
        _hasPendingLocalEdits = false;
      });
      _showSnackBar("Order items saved");
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSavingItems = false;
      });
      _showSnackBar("Could not save order items");
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(leadsControllerProvider.notifier);
    final leads = ref.watch(leadsControllerProvider);

    final liveOrder = leads.firstWhere(
      (lead) => lead["id"].toString() == widget.order["id"].toString(),
      orElse: () => widget.order,
    );

    final sourceItems = (liveOrder["items"] ?? []) as List;
    _syncDraftItems(sourceItems);

    final phone = (liveOrder["phone"] ?? "").toString();
    final name = (liveOrder["name"] ?? "Customer").toString();
    final status = (liveOrder["order_status"] ?? "pending").toString();
    final createdAt = _parseDate(liveOrder["created_at"]);
    final completedAt = _parseDate(liveOrder["completed_at"]);
    final subtotal = _calculateAmount(liveOrder, _draftItems);
    final total = subtotal;
    final totalUnits = _totalUnits(_draftItems);

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
                        "₹${_currency(total)}",
                        const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _heroStat(
                        "Units",
                        totalUnits.toString(),
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
                () => _whatsapp(phone, name),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                "Call",
                FontAwesomeIcons.phone,
                const Color(0xFF6C4ED9),
                () => _call(phone, name),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                status == "completed" ? "Done" : "Start order",
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
                            controller,
                            liveOrder,
                            "processing",
                            "Order moved to processing",
                          );
                        } else {
                          _updateStatus(
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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Items",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openItemEditor(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text("Add item"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_draftItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "No items added yet. Add your first item to calculate totals properly.",
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ..._draftItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDE7FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    _quantity(item).toString(),
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
                                      _productName(item),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "₹${_currency(_price(item))} each",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "₹${_currency(_lineTotal(item))}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _miniItemAction(
                                label: "Edit",
                                icon: Icons.edit_outlined,
                                color: const Color(0xFF6C4ED9),
                                onTap: () => _openItemEditor(
                                  existingItem: item,
                                  index: index,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _miniItemAction(
                                label: "Remove",
                                icon: Icons.delete_outline_rounded,
                                color: const Color(0xFFDC2626),
                                onTap: () => _removeItem(index),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _summaryRow("Subtotal", "₹${_currency(subtotal)}"),
                _summaryRow("Line Items", _draftItems.length.toString()),
                _summaryRow("Units", totalUnits.toString()),
                _summaryRow(
                  "Status",
                  status == "processing"
                      ? "In Progress"
                      : status == "completed"
                      ? "Completed"
                      : "Pending",
                ),
                const SizedBox(height: 8),
                _summaryRow("Total", "₹${_currency(total)}", isTotal: true),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSavingItems
                        ? null
                        : () => _saveItems(controller, liveOrder),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4ED9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _isSavingItems ? "Saving..." : "Save Order Items",
                    ),
                  ),
                ),
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

  Widget _miniItemAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
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
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
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

class _OrderItemEditorSheet extends StatefulWidget {
  const _OrderItemEditorSheet({this.item});

  final Map<String, dynamic>? item;

  @override
  State<_OrderItemEditorSheet> createState() => _OrderItemEditorSheetState();
}

class _OrderItemEditorSheetState extends State<_OrderItemEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text:
          (widget.item?["product_name"] ??
                  widget.item?["product"] ??
                  widget.item?["name"] ??
                  "")
              .toString(),
    );
    _quantityController = TextEditingController(
      text: (widget.item?["quantity"] ?? widget.item?["qty"] ?? 1).toString(),
    );
    _priceController = TextEditingController(
      text: (widget.item?["price"] ?? "").toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  int _asInt(String value, {int fallback = 0}) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  double _asDouble(String value) {
    return double.tryParse(value.trim()) ?? 0;
  }

  void _submit() {
    final name = _nameController.text.trim();
    final quantity = _asInt(_quantityController.text, fallback: 0);
    final price = _asDouble(_priceController.text);

    if (name.isEmpty || quantity <= 0 || price < 0) {
      setState(() {
        _errorText = "Enter a valid item, qty, and price";
      });
      return;
    }

    Navigator.of(context).pop({
      "product_name": name,
      "quantity": quantity,
      "price": price,
      "total": quantity * price,
    });
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required TextInputType keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item == null ? "Add Item" : "Edit Item",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _nameController,
            label: "Product name",
            keyboardType: TextInputType.name,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _quantityController,
                  label: "Qty",
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  controller: _priceController,
                  label: "Price",
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C4ED9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(widget.item == null ? "Add item" : "Save item"),
            ),
          ),
        ],
      ),
    );
  }
}
