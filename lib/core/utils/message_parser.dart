class MessageParser {
  static Map<String, dynamic> parse(String text) {
    final lower = text.toLowerCase();

    return {
      "raw": text,
      "name": _extractName(text),
      "items": _extractItems(lower),
      "intent": _detectIntent(lower),
      "date": _detectDate(lower),
      "type": _detectType(lower),
    };
  }

  /// 👤 NAME (simple heuristic: first capitalized word)
  static String? _extractName(String text) {
    final words = text.split(" ");
    if (words.isEmpty) return null;

    final first = words.first;

    if (first.isNotEmpty && first[0].toUpperCase() == first[0]) {
      return first;
    }

    return null;
  }

  /// 📦 ITEMS (quantity + product)
  static List<Map<String, dynamic>> _extractItems(String text) {
    final words = text.split(" ");
    final items = <Map<String, dynamic>>[];

    for (int i = 0; i < words.length; i++) {
      final quantity = int.tryParse(words[i]);

      if (quantity != null && i + 1 < words.length) {
        final product = words[i + 1];

        items.add({
          "product": product,
          "quantity": quantity,
        });
      }
    }

    return items;
  }

  /// 🧠 INTENT
  static String _detectIntent(String text) {
    if (text.contains("confirm") || text.contains("order")) {
      return "order";
    }

    if (text.contains("later") ||
        text.contains("tomorrow") ||
        text.contains("call") ||
        text.contains("follow")) {
      return "follow_up";
    }

    return "inquiry";
  }

  /// 📅 DATE
  static DateTime? _detectDate(String text) {
    final now = DateTime.now();

    if (text.contains("tomorrow")) {
      return now.add(const Duration(days: 1));
    }

    if (text.contains("today")) {
      return now;
    }

    return null;
  }

  /// 🏷 TYPE
  static String _detectType(String text) {
    if (text.contains("order") || text.contains("confirm")) {
      return "order";
    }

    if (text.contains("later") || text.contains("follow")) {
      return "follow_up";
    }

    return "lead";
  }
}