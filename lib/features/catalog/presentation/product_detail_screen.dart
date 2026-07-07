import 'package:flutter/material.dart';

import '../data/product.dart';

/// Placeholder — full implementation in the ProductDetailScreen task.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: const Center(child: Text('Coming in the next commit')),
    );
  }
}
