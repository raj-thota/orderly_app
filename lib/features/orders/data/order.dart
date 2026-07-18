import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/payments/data/payment.dart';

class OrderItem {
  const OrderItem({
    required this.name,
    this.imageUrl,
    this.unitPrice = 0,
    this.qty = 1,
    this.lineTotal = 0,
    this.gstRate = 0,
    this.productId,
    this.type = 'product',
  });

  final String name;
  final String? imageUrl;
  final double unitPrice;
  final int qty;
  final double lineTotal;
  final double gstRate;
  final String? productId;
  final String type;

  ItemType get itemType => ItemType.fromId(type);

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: (map['name'] ?? 'Item').toString(),
      imageUrl: map['image_url'] as String?,
      unitPrice: double.tryParse(map['unit_price']?.toString() ?? '') ?? 0,
      qty: int.tryParse(map['qty']?.toString() ?? '') ?? 1,
      lineTotal: double.tryParse(map['line_total']?.toString() ?? '') ?? 0,
      gstRate: double.tryParse(map['gst_rate']?.toString() ?? '') ?? 0,
      productId: map['product_id']?.toString(),
      type: (map['item_type'] ?? 'product').toString(),
    );
  }
}

class Order {
  const Order({
    this.id,
    this.orderNumber,
    this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.status = 'confirmed',
    this.courier,
    this.trackingNo,
    this.shippedAt,
    this.deliveredAt,
    this.paymentStatus = 'unpaid',
    this.subtotal = 0,
    this.grandTotal = 0,
    this.discount = 0,
    this.shippingFee = 0,
    this.expectedDate,
    this.notes,
    this.createdAt,
    this.items = const [],
    this.payments = const [],
  });

  final String? id;
  final int? orderNumber;
  final String? invoiceNumber;
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
  final double discount;
  final double shippingFee;
  final DateTime? expectedDate;
  final String? notes;
  final DateTime? createdAt;
  final List<OrderItem> items;
  final List<Payment> payments;

  double get paidTotal => payments.fold<double>(0, (sum, p) => sum + p.amount);
  double get dues {
    // Round to paise so floating-point residue (e.g. 100 - 33.33*3) can't leave
    // a ~1e-12 balance that shows the pay actions while the server reads 'paid'.
    final d = ((grandTotal - paidTotal) * 100).round() / 100;
    return d > 0 ? d : 0;
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    final itemsRaw = map['order_items'] as List? ?? const [];
    final paymentsRaw = map['payments'] as List? ?? const [];
    return Order(
      id: map['id']?.toString(),
      orderNumber: int.tryParse(map['order_number']?.toString() ?? ''),
      invoiceNumber: map['invoice_number']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
      status: (map['status'] ?? 'confirmed').toString(),
      courier: map['courier']?.toString(),
      trackingNo: map['tracking_no']?.toString(),
      shippedAt: DateTime.tryParse(map['shipped_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? ''),
      paymentStatus: (map['payment_status'] ?? 'unpaid').toString(),
      subtotal: double.tryParse(map['subtotal']?.toString() ?? '') ?? 0,
      grandTotal: double.tryParse(map['grand_total']?.toString() ?? '') ?? 0,
      discount: double.tryParse(map['discount']?.toString() ?? '') ?? 0,
      shippingFee: double.tryParse(map['shipping_fee']?.toString() ?? '') ?? 0,
      expectedDate: DateTime.tryParse(map['expected_date']?.toString() ?? ''),
      notes: map['notes']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      items: [
        for (final i in itemsRaw)
          if (i is Map) OrderItem.fromMap(Map<String, dynamic>.from(i)),
      ],
      payments: [
        for (final p in paymentsRaw)
          if (p is Map) Payment.fromMap(Map<String, dynamic>.from(p)),
      ],
    );
  }
}
