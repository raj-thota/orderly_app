import 'item_type.dart';

/// A catalog product. `isUnique` pieces track availability via [pieceStatus]
/// (available/booked/sold); stocked items track [qtyOnHand].
class Product {
  const Product({
    this.id,
    required this.name,
    this.description,
    this.sku,
    this.images = const [],
    this.price = 0,
    this.unit = 'pc',
    this.gstRate,
    this.isUnique = false,
    this.pieceStatus = 'available',
    this.qtyOnHand = 0,
    this.active = true,
    this.createdAt,
    this.type = 'product',
    this.category,
    this.duration,
    this.deliveryMethod,
  });

  final String? id;
  final String name;
  final String? description;
  final String? sku;
  final List<String> images;
  final double price;
  final String unit;
  final double? gstRate;
  final bool isUnique;
  final String pieceStatus;
  final int qtyOnHand;
  final bool active;
  final DateTime? createdAt;
  final String type;
  final String? category;
  final String? duration;
  final String? deliveryMethod;

  ItemType get itemType => ItemType.fromId(type);

  bool get isAvailable => isUnique ? pieceStatus == 'available' : qtyOnHand > 0;

  String? get coverImage => images.isEmpty ? null : images.first;

  Product copyWith({
    int? qtyOnHand,
    String? pieceStatus,
    String? type,
    String? category,
    String? duration,
    String? deliveryMethod,
  }) {
    return Product(
      id: id,
      name: name,
      description: description,
      sku: sku,
      images: images,
      price: price,
      unit: unit,
      gstRate: gstRate,
      isUnique: isUnique,
      pieceStatus: pieceStatus ?? this.pieceStatus,
      qtyOnHand: qtyOnHand ?? this.qtyOnHand,
      active: active,
      createdAt: createdAt,
      type: type ?? this.type,
      category: category ?? this.category,
      duration: duration ?? this.duration,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
    );
  }

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static double? _asDoubleOrNull(dynamic v) {
    if (v == null) return null;
    return v is num ? v.toDouble() : double.tryParse(v.toString());
  }

  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
      sku: map['sku']?.toString(),
      images:
          (map['images'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      price: _asDouble(map['price']),
      unit: (map['unit'] ?? 'pc').toString(),
      gstRate: _asDoubleOrNull(map['gst_rate']),
      isUnique: map['is_unique'] == true,
      pieceStatus: (map['piece_status'] ?? 'available').toString(),
      qtyOnHand: _asInt(map['qty_on_hand'], 0),
      active: map['active'] != false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      type: (map['type'] ?? 'product').toString(),
      category: map['category']?.toString(),
      duration: map['duration']?.toString(),
      deliveryMethod: map['delivery_method']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'sku': sku,
        'images': images,
        'price': price,
        'unit': unit,
        'gst_rate': gstRate,
        'is_unique': isUnique,
        'piece_status': pieceStatus,
        'qty_on_hand': qtyOnHand,
        'active': active,
        'type': type,
        'category': category,
        'duration': duration,
        'delivery_method': deliveryMethod,
      };
}
