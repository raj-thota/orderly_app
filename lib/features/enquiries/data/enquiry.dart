enum EnquiryBucket { overdue, today, upcoming, fresh }

class Enquiry {
  const Enquiry({
    this.id,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.productId,
    this.productName,
    this.productImage,
    this.productIsUnique = false,
    this.productPrice,
    this.source = 'manual',
    this.message,
    this.screenshotUrl,
    this.intent,
    this.status = 'new',
    this.followUpDate,
    this.followUpNote,
    this.activities = const [],
    this.createdAt,
  });

  final String? id;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? productId;
  final String? productName;
  final String? productImage;
  final bool productIsUnique;
  final double? productPrice;
  final String source;
  final String? message;
  final String? screenshotUrl;
  final String? intent;
  final String status;
  final DateTime? followUpDate;
  final String? followUpNote;
  final List<Map<String, dynamic>> activities;
  final DateTime? createdAt;

  factory Enquiry.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    final product = map['products'];
    final images =
        product is Map ? (product['images'] as List? ?? const []) : const [];
    return Enquiry(
      id: map['id']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
      customerEmail: customer is Map ? customer['email']?.toString() : null,
      productId: map['product_id']?.toString(),
      productName: product is Map ? product['name']?.toString() : null,
      productImage: images.isEmpty ? null : images.first.toString(),
      productIsUnique: product is Map && product['is_unique'] == true,
      productPrice: product is Map
          ? double.tryParse(product['price']?.toString() ?? '')
          : null,
      source: (map['source'] ?? 'manual').toString(),
      message: map['message']?.toString(),
      screenshotUrl: map['screenshot_url'] as String?,
      intent: map['intent']?.toString(),
      status: (map['status'] ?? 'new').toString(),
      followUpDate:
          DateTime.tryParse(map['follow_up_date']?.toString() ?? ''),
      followUpNote: map['follow_up_note']?.toString(),
      activities: [
        for (final a in (map['activities'] as List? ?? const []))
          if (a is Map) Map<String, dynamic>.from(a),
      ],
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  EnquiryBucket bucket(DateTime now) {
    final due = followUpDate;
    if (status == 'follow' && due != null) {
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startOfTomorrow = startOfToday.add(const Duration(days: 1));
      if (due.isBefore(startOfToday)) return EnquiryBucket.overdue;
      if (due.isBefore(startOfTomorrow)) return EnquiryBucket.today;
      return EnquiryBucket.upcoming;
    }
    return EnquiryBucket.fresh;
  }
}
