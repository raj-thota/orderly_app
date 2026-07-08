/// Builds a UPI intent URI (`upi://pay?...`). The VPA and amount are left raw
/// (the `@` in a VPA is a valid query char; the amount is numeric); the payee
/// name and transaction note are URL-encoded.
String buildUpiUri({
  required String vpa,
  String? name,
  required double amount,
  String? note,
}) {
  final parts = <String>[
    'pa=$vpa',
    'am=${amount.toStringAsFixed(2)}',
    'cu=INR',
  ];
  if (name != null && name.isNotEmpty) {
    parts.add('pn=${Uri.encodeComponent(name)}');
  }
  if (note != null && note.isNotEmpty) {
    parts.add('tn=${Uri.encodeComponent(note)}');
  }
  return 'upi://pay?${parts.join('&')}';
}
