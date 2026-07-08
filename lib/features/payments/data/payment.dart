class Payment {
  const Payment({
    required this.amount,
    this.method = 'upi',
    this.paidAt,
  });

  final double amount;
  final String method;
  final DateTime? paidAt;

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      amount: double.tryParse(map['amount']?.toString() ?? '') ?? 0,
      method: (map['method'] ?? 'upi').toString(),
      paidAt: DateTime.tryParse(map['paid_at']?.toString() ?? ''),
    );
  }
}
