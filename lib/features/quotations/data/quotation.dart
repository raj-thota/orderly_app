import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';

/// One priced line in a quotation.
class QuoteLine {
  const QuoteLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  final String name;
  final int qty;
  final double unitPrice;

  double get lineTotal => unitPrice * qty;
}

/// Fuzzy-matches parsed draft items against active catalog products
/// (case-insensitive substring, either direction). A match adopts the
/// product's canonical name and, when the item has no price, its price.
/// Unmatched items stay free-text with the item's price or 0.
List<QuoteLine> matchCatalog(List<DraftItem> items, List<Product> products) {
  final lines = <QuoteLine>[];
  for (final item in items) {
    final needle = item.name.trim().toLowerCase();
    Product? match;
    for (final p in products) {
      final hay = p.name.trim().toLowerCase();
      if (needle.isEmpty) break;
      if (hay.contains(needle) || needle.contains(hay)) {
        match = p;
        break;
      }
    }
    lines.add(QuoteLine(
      name: match?.name ?? item.name,
      qty: item.qty,
      unitPrice: item.price ?? match?.price ?? 0,
    ));
  }
  return lines;
}

/// A composed quotation: the shareable message plus its numeric total.
class Quotation {
  const Quotation(
      {required this.lines, required this.total, required this.message});

  final List<QuoteLine> lines;
  final double total;
  final String message;

  static Quotation compose({
    required String businessName,
    required String? upiId,
    required String? upiName,
    required String? customerName,
    required List<QuoteLine> lines,
  }) {
    final total = lines.fold<double>(0, (sum, l) => sum + l.lineTotal);

    final buffer = StringBuffer()
      ..writeln(businessName)
      ..writeln(customerName == null || customerName.isEmpty
          ? 'Quotation'
          : 'Quotation for $customerName')
      ..writeln();

    for (final l in lines) {
      buffer.writeln(
          '${l.name} x ${l.qty} @ ${Money.inr(l.unitPrice)} = ${Money.inr(l.lineTotal)}');
    }

    buffer
      ..writeln()
      ..writeln('Total: ${Money.inr(total)}');

    if (upiId != null && upiId.isNotEmpty) {
      final who = (upiName != null && upiName.isNotEmpty) ? ' ($upiName)' : '';
      buffer.writeln('Pay via UPI: $upiId$who');
    }

    return Quotation(
      lines: lines,
      total: total,
      message: buffer.toString().trimRight(),
    );
  }
}
