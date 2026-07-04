/// INR money formatting with Indian digit grouping (e.g. 12,34,567).
class Money {
  Money._();

  static String inr(num value, {bool symbol = true}) {
    final negative = value < 0;
    final abs = value.abs();
    final isWhole = abs == abs.roundToDouble();
    final fixed = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);

    final parts = fixed.split('.');
    final grouped = _groupIndian(parts[0]);
    final decimals = parts.length > 1 ? '.${parts[1]}' : '';

    return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped$decimals';
  }

  /// Groups the integer part: last 3 digits, then in pairs. 1234567 -> 12,34,567
  static String _groupIndian(String intPart) {
    if (intPart.length <= 3) return intPart;
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '${groups.join(',')},$last3';
  }
}
