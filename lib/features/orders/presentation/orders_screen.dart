import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import '../widgets/orders_list.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  int selectedTab = 0;

  final tabs = ["Pending", "In Progress", "Completed"];

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? "0") ?? 0;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  double _orderTotal(Map<String, dynamic> order) {
    final items = order["items"];
    if (items is! List) return 0;

    return items.fold<double>(0, (sum, item) {
      final map = Map<String, dynamic>.from(item);
      final total = _asDouble(map["total"]);
      if (total > 0) return sum + total;

      final qty = _asInt(map["quantity"] ?? map["qty"], fallback: 1);
      final price = _asDouble(map["price"]);
      return sum + (qty * price);
    });
  }

  String _currency(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersControllerProvider);

    final pending = orders
        .where((o) => o["order_status"] == "pending")
        .toList();

    final inProgress = orders
        .where((o) => o["order_status"] == "processing")
        .toList();

    final completed = orders
        .where((o) => o["order_status"] == "completed")
        .toList();

    final revenue = orders.fold<double>(0, (sum, o) {
      return sum + _orderTotal(o);
    });

    final filtered = selectedTab == 0
        ? pending
        : selectedTab == 1
        ? inProgress
        : completed;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text("Orders")),
      body: Column(
        children: [
          /// STATS
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C4EFF), Color(0xFF8E7CFF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Total Revenue",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  "₹${_currency(revenue)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat("Orders", orders.length),
                    _miniStat("Pending", pending.length),
                    _miniStat("Done", completed.length),
                  ],
                ),
              ],
            ),
          ),

          /// TABS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: List.generate(tabs.length, (index) {
                  final isActive = selectedTab == index;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedTab = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            "${tabs[index]} (${index == 0
                                ? pending.length
                                : index == 1
                                ? inProgress.length
                                : completed.length})",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          const SizedBox(height: 10),

          /// LIST
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: filtered.isEmpty
                  ? _emptyState()
                  : OrdersList(
                      key: ValueKey(filtered.length.toString()),
                      orders: filtered,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        const Text(
          "No orders yet",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          "Convert leads to start tracking orders",
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _miniStat(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
