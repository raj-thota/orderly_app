class Customer {
  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.tags = const [],
    this.createdAt,
  });

  final String? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final List<String> tags;
  final DateTime? createdAt;

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      address: map['address']?.toString(),
      notes: map['notes']?.toString(),
      tags: [for (final t in (map['tags'] as List? ?? const [])) t.toString()],
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
        if (notes != null) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
      };
}
