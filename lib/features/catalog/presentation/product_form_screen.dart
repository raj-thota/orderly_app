import 'package:flutter/material.dart';

import '../data/product.dart';

/// Placeholder — full implementation in the ProductFormScreen task.
class ProductFormScreen extends StatelessWidget {
  const ProductFormScreen({super.key, this.existing});

  final Product? existing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(existing == null ? 'Add piece' : 'Edit piece')),
      body: const Center(child: Text('Coming in the next commit')),
    );
  }
}
