import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/orders_provider.dart';
import '../data/order.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderFilter _filter = OrderFilter.active;
  String _search = '';
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<Order> _applySearch(List<Order> orders) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return orders;
    return orders.where((o) {
      return (o.customerName ?? '').toLowerCase().contains(q) ||
          (o.orderNumber?.toString() ?? '').contains(q);
    }).toList();
  }

  static const _chips = [
    (OrderFilter.active, 'Active'),
    (OrderFilter.confirmed, 'Confirmed'),
    (OrderFilter.packed, 'Packed'),
    (OrderFilter.shipped, 'Shipped'),
    (OrderFilter.delivered, 'Delivered'),
    (OrderFilter.cancelled, 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Orders',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: 'Search by customer or order #',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() => _search = '');
                              })
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: async.maybeWhen(
                data: (orders) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    for (final (filter, label) in _chips)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(
                              '$label (${filterOrders(orders, filter).length})'),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load orders'),
                      TextButton(
                        onPressed: () => ref
                            .read(ordersControllerProvider.notifier)
                            .load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (orders) {
                  final filtered = _applySearch(filterOrders(orders, _filter));
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text(
                        'No orders yet.\nConvert an enquiry to start fulfilling.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(ordersControllerProvider.notifier).load(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, 96),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: OrderCard(
                          order: filtered[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailScreen(order: filtered[i])),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
