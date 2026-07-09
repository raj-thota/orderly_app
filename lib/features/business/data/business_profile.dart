class BusinessProfile {
  const BusinessProfile({
    this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.upiId,
    this.upiName,
    this.gstin,
    this.defaultGstRate = 0,
    this.invoicePrefix = 'INV-',
    this.nextInvoiceNumber = 1,
    this.currency = 'INR',
    this.invoiceTemplate = 'classic',
  });

  final String? id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? upiId;
  final String? upiName;
  final String? gstin;
  final double defaultGstRate;
  final String invoicePrefix;
  final int nextInvoiceNumber;
  final String currency;
  final String invoiceTemplate;

  bool get hasGst => (gstin ?? '').trim().isNotEmpty;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      logoUrl: map['logo_url']?.toString(),
      address: map['address']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      upiId: map['upi_id']?.toString(),
      upiName: map['upi_name']?.toString(),
      gstin: map['gstin']?.toString(),
      defaultGstRate: _asDouble(map['default_gst_rate']),
      invoicePrefix: (map['invoice_prefix'] ?? 'INV-').toString(),
      nextInvoiceNumber: _asInt(map['next_invoice_number'], 1),
      currency: (map['currency'] ?? 'INR').toString(),
      invoiceTemplate: (map['invoice_template'] ?? 'classic').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'logo_url': logoUrl,
        'address': address,
        'phone': phone,
        'email': email,
        'upi_id': upiId,
        'upi_name': upiName,
        'gstin': gstin,
        'default_gst_rate': defaultGstRate,
        'currency': currency,
        'invoice_template': invoiceTemplate,
      };

  BusinessProfile copyWith({
    String? name,
    String? address,
    String? phone,
    String? upiId,
    String? upiName,
    String? gstin,
    double? defaultGstRate,
    String? invoiceTemplate,
  }) {
    return BusinessProfile(
      id: id,
      name: name ?? this.name,
      logoUrl: logoUrl,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email,
      upiId: upiId ?? this.upiId,
      upiName: upiName ?? this.upiName,
      gstin: gstin ?? this.gstin,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      invoicePrefix: invoicePrefix,
      nextInvoiceNumber: nextInvoiceNumber,
      currency: currency,
      invoiceTemplate: invoiceTemplate ?? this.invoiceTemplate,
    );
  }
}
