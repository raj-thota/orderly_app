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
    this.ownerName,
    this.city,
    this.state,
    this.pincode,
    this.pan,
    this.businessType,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.defaultPaymentMethod,
    this.gstEnabled = false,
    this.paymentTerms,
    this.invoiceFooter,
    this.signatureUrl,
    this.language = 'en',
    this.timezone = 'Asia/Kolkata',
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

  // Phase 1 additions
  final String? ownerName;
  final String? city;
  final String? state;
  final String? pincode;
  final String? pan;
  final String? businessType;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? defaultPaymentMethod;
  final bool gstEnabled;
  final String? paymentTerms;
  final String? invoiceFooter;
  final String? signatureUrl;
  final String language;
  final String timezone;

  bool get hasGst => (gstin ?? '').trim().isNotEmpty;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
  static bool _asBool(dynamic v) =>
      v is bool ? v : v?.toString().toLowerCase() == 'true';
  static String? _str(dynamic v) => v?.toString();

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      logoUrl: _str(map['logo_url']),
      address: _str(map['address']),
      phone: _str(map['phone']),
      email: _str(map['email']),
      upiId: _str(map['upi_id']),
      upiName: _str(map['upi_name']),
      gstin: _str(map['gstin']),
      defaultGstRate: _asDouble(map['default_gst_rate']),
      invoicePrefix: (map['invoice_prefix'] ?? 'INV-').toString(),
      nextInvoiceNumber: _asInt(map['next_invoice_number'], 1),
      currency: (map['currency'] ?? 'INR').toString(),
      invoiceTemplate: (map['invoice_template'] ?? 'classic').toString(),
      ownerName: _str(map['owner_name']),
      city: _str(map['city']),
      state: _str(map['state']),
      pincode: _str(map['pincode']),
      pan: _str(map['pan']),
      businessType: _str(map['business_type']),
      bankAccountName: _str(map['bank_account_name']),
      bankAccountNumber: _str(map['bank_account_number']),
      bankIfsc: _str(map['bank_ifsc']),
      defaultPaymentMethod: _str(map['default_payment_method']),
      gstEnabled: _asBool(map['gst_enabled']),
      paymentTerms: _str(map['payment_terms']),
      invoiceFooter: _str(map['invoice_footer']),
      signatureUrl: _str(map['signature_url']),
      language: (map['language'] ?? 'en').toString(),
      timezone: (map['timezone'] ?? 'Asia/Kolkata').toString(),
    );
  }

  /// Client-writable columns only. Deliberately omits invoice_prefix /
  /// next_invoice_number (DB-owned; bumped by assign_invoice_number). Use
  /// BusinessProfileService.updateInvoiceNumbering to change those.
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
        'owner_name': ownerName,
        'city': city,
        'state': state,
        'pincode': pincode,
        'pan': pan,
        'business_type': businessType,
        'bank_account_name': bankAccountName,
        'bank_account_number': bankAccountNumber,
        'bank_ifsc': bankIfsc,
        'default_payment_method': defaultPaymentMethod,
        'gst_enabled': gstEnabled,
        'payment_terms': paymentTerms,
        'invoice_footer': invoiceFooter,
        'signature_url': signatureUrl,
        'language': language,
        'timezone': timezone,
      };

  BusinessProfile copyWith({
    String? name,
    String? logoUrl,
    String? address,
    String? phone,
    String? email,
    String? upiId,
    String? upiName,
    String? gstin,
    double? defaultGstRate,
    String? currency,
    String? invoiceTemplate,
    String? ownerName,
    String? city,
    String? state,
    String? pincode,
    String? pan,
    String? businessType,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? defaultPaymentMethod,
    bool? gstEnabled,
    String? paymentTerms,
    String? invoiceFooter,
    String? signatureUrl,
    String? language,
    String? timezone,
  }) {
    return BusinessProfile(
      id: id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      upiId: upiId ?? this.upiId,
      upiName: upiName ?? this.upiName,
      gstin: gstin ?? this.gstin,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      invoicePrefix: invoicePrefix,
      nextInvoiceNumber: nextInvoiceNumber,
      currency: currency ?? this.currency,
      invoiceTemplate: invoiceTemplate ?? this.invoiceTemplate,
      ownerName: ownerName ?? this.ownerName,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      pan: pan ?? this.pan,
      businessType: businessType ?? this.businessType,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      gstEnabled: gstEnabled ?? this.gstEnabled,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      invoiceFooter: invoiceFooter ?? this.invoiceFooter,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
    );
  }
}
