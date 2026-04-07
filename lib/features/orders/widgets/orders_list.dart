import 'package:flutter/material.dart';
import 'order_card.dart';

class OrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;

  const OrdersList({super.key, required this.orders});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (_, i) {
        final order = orders[i];

        return TweenAnimationBuilder(
          duration: Duration(milliseconds: 300 + (i * 50)),
          tween: Tween<double>(begin: 0, end: 1),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: OrderCard(order: order),
        );
      },
    );
  }
}
