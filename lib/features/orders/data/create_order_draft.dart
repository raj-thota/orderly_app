class CreateOrderItem {
  const CreateOrderItem({
    required this.name,
    this.qty = 1,
    this.unitPrice = 0,
    this.productId,
  });

  final String name;
  final int qty;
  final double unitPrice;
  final String? productId;

  double get lineTotal => qty * unitPrice;

  CreateOrderItem copyWith({String? name, int? qty, double? unitPrice}) =>
      CreateOrderItem(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        productId: productId,
      );
}

class CreateOrderDraft {
  const CreateOrderDraft({
    required this.customerId,
    required this.customerName,
    this.items = const [],
    this.discount = 0,
    this.shippingFee = 0,
    this.expectedDate,
    this.notes,
  });

  final String customerId;
  final String customerName;
  final List<CreateOrderItem> items;
  final double discount;
  final double shippingFee;
  final DateTime? expectedDate;
  final String? notes;

  double get subtotal => items.fold(0.0, (s, i) => s + i.lineTotal);
  double get grandTotal {
    final v = subtotal - discount + shippingFee;
    return v < 0 ? 0 : v;
  }
  bool get canSubmit => items.isNotEmpty && (subtotal - discount + shippingFee) >= 0;

  CreateOrderDraft copyWith({
    List<CreateOrderItem>? items,
    double? discount,
    double? shippingFee,
    DateTime? expectedDate,
    String? notes,
  }) =>
      CreateOrderDraft(
        customerId: customerId,
        customerName: customerName,
        items: items ?? this.items,
        discount: discount ?? this.discount,
        shippingFee: shippingFee ?? this.shippingFee,
        expectedDate: expectedDate ?? this.expectedDate,
        notes: notes ?? this.notes,
      );
}
