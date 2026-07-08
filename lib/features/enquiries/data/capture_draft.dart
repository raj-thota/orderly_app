class DraftItem {
  const DraftItem({required this.name, this.qty = 1, this.price});
  final String name;
  final int qty;
  final double? price;

  DraftItem copyWith({String? name, int? qty, double? price}) =>
      DraftItem(name: name ?? this.name, qty: qty ?? this.qty, price: price ?? this.price);
}

/// Rules-based parse of a pasted chat / spoken summary. AI refinement (Slice B)
/// layers on top of this shape; saving never depends on the AI result.
class CaptureDraft {
  const CaptureDraft({
    this.name,
    this.phone,
    this.items = const [],
    this.intent = 'inquiry',
    this.type = 'enquiry',
    this.followUpDate,
    this.raw = '',
  });

  final String? name;
  final String? phone;
  final List<DraftItem> items;
  final String intent; // inquiry | order | follow_up
  final String type; // enquiry | order
  final DateTime? followUpDate;
  final String raw;

  bool get isEmpty =>
      name == null && phone == null && items.isEmpty && raw.trim().isEmpty;

  CaptureDraft copyWith({
    String? name,
    String? phone,
    List<DraftItem>? items,
    String? intent,
    String? type,
    DateTime? followUpDate,
    bool clearFollowUp = false,
  }) =>
      CaptureDraft(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        items: items ?? this.items,
        intent: intent ?? this.intent,
        type: type ?? this.type,
        followUpDate: clearFollowUp ? null : (followUpDate ?? this.followUpDate),
        raw: raw,
      );

  static final _phoneRe =
      RegExp(r'(?<!\d)(?:\+?91[\s-]?)?([6-9]\d{4}[\s-]?\d{5})(?!\d)');

  /// Digits-only phone: strips formatting and a leading country code / trunk
  /// zero so the same number always dedupes and deep-links cleanly.
  static String? normalizePhone(String? raw) {
    if (raw == null) return null;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits.isEmpty ? null : digits;
  }
  static final _nameRe = RegExp(
      r"(?:this is|i am|i'm|from)\s+([A-Z][a-z]+)|^([A-Z][a-z]+):",
      caseSensitive: false);
  // Require whitespace or start-of-string before qty so digits inside prices
  // like "₹1,500" (where "500" follows a comma) are never captured as a qty.
  static final _itemRe = RegExp(r'(?:^|\s)(\d{1,3})\s+([a-z]+)');
  static final _priceRe =
      RegExp(r'(?:₹|rs\.?|rupees?|at|@)\s*([\d,]+)', caseSensitive: false);

  factory CaptureDraft.fromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return CaptureDraft(raw: text);
    final lower = trimmed.toLowerCase();

    final phoneMatch = _phoneRe.firstMatch(trimmed);
    final phone = phoneMatch?.group(1)?.replaceAll(RegExp(r'[\s-]'), '');

    final nameMatch = _nameRe.firstMatch(trimmed);
    String? name = nameMatch?.group(1) ?? nameMatch?.group(2);
    if (name != null) {
      name = name[0].toUpperCase() + name.substring(1);
    }

    final items = <DraftItem>[];
    for (final m in _itemRe.allMatches(lower)) {
      final qty = int.parse(m.group(1)!);
      final word = m.group(2)!;
      // Skip time words that follow numbers ("2 days", "3 pm").
      if (const {'days', 'day', 'pm', 'am', 'weeks', 'week'}.contains(word)) {
        continue;
      }
      // Price if a rupee amount appears within 20 chars after the item word.
      final tail = lower.substring(
          m.end, m.end + 20 > lower.length ? lower.length : m.end + 20);
      final priceMatch = _priceRe.firstMatch(tail);
      final price = priceMatch == null
          ? null
          : double.tryParse(priceMatch.group(1)!.replaceAll(',', ''));
      items.add(DraftItem(name: word, qty: qty, price: price));
    }

    // Require "order" or "book" for order detection — bare "confirm" alone
    // does NOT indicate an order (e.g. "will confirm tomorrow" is an enquiry).
    final isOrder = lower.contains('order') || lower.contains('book');
    final wantsFollowUp = lower.contains('later') ||
        lower.contains('tomorrow') ||
        lower.contains('next week') ||
        lower.contains('call me') ||
        lower.contains('follow');

    DateTime? followUp;
    final now = DateTime.now();
    if (lower.contains('day after tomorrow')) {
      followUp = now.add(const Duration(days: 2));
    } else if (lower.contains('tomorrow')) {
      followUp = now.add(const Duration(days: 1));
    } else if (lower.contains('next week')) {
      followUp = now.add(const Duration(days: 7));
    } else if (lower.contains('today')) {
      followUp = now;
    }

    final resolvedIntent =
        isOrder ? 'order' : (wantsFollowUp ? 'follow_up' : 'inquiry');

    // A follow-up with no explicit date still needs one so the reminder
    // engine can schedule it; default to +2 days (user can change it).
    if (followUp == null && resolvedIntent == 'follow_up') {
      followUp = now.add(const Duration(days: 2));
    }

    return CaptureDraft(
      name: name,
      phone: phone,
      items: items,
      intent: resolvedIntent,
      type: isOrder ? 'order' : 'enquiry',
      followUpDate: followUp,
      raw: text,
    );
  }
}
