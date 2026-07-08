class OrderItem {
  const OrderItem({
    required this.name,
    this.imageUrl,
    this.unitPrice = 0,
    this.qty = 1,
    this.lineTotal = 0,
    this.productId,
  });

  final String name;
  final String? imageUrl;
  final double unitPrice;
  final int qty;
  final double lineTotal;
  final String? productId;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: (map['name'] ?? 'Item').toString(),
      imageUrl: map['image_url'] as String?,
      unitPrice: double.tryParse(map['unit_price']?.toString() ?? '') ?? 0,
      qty: int.tryParse(map['qty']?.toString() ?? '') ?? 1,
      lineTotal: double.tryParse(map['line_total']?.toString() ?? '') ?? 0,
      productId: map['product_id']?.toString(),
    );
  }
}

class Order {
  const Order({
    this.id,
    this.orderNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.status = 'pending',
    this.courier,
    this.trackingNo,
    this.shippedAt,
    this.deliveredAt,
    this.paymentStatus = 'unpaid',
    this.subtotal = 0,
    this.grandTotal = 0,
    this.notes,
    this.createdAt,
    this.items = const [],
  });

  final String? id;
  final int? orderNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final String? courier;
  final String? trackingNo;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final String paymentStatus;
  final double subtotal;
  final double grandTotal;
  final String? notes;
  final DateTime? createdAt;
  final List<OrderItem> items;

  factory Order.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    final itemsRaw = map['order_items'] as List? ?? const [];
    return Order(
      id: map['id']?.toString(),
      orderNumber: int.tryParse(map['order_number']?.toString() ?? ''),
      customerId: map['customer_id']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
      status: (map['status'] ?? 'pending').toString(),
      courier: map['courier']?.toString(),
      trackingNo: map['tracking_no']?.toString(),
      shippedAt: DateTime.tryParse(map['shipped_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? ''),
      paymentStatus: (map['payment_status'] ?? 'unpaid').toString(),
      subtotal: double.tryParse(map['subtotal']?.toString() ?? '') ?? 0,
      grandTotal: double.tryParse(map['grand_total']?.toString() ?? '') ?? 0,
      notes: map['notes']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      items: [
        for (final i in itemsRaw)
          if (i is Map) OrderItem.fromMap(Map<String, dynamic>.from(i)),
      ],
    );
  }
}
