import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/data/upi.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Money for the PDF: Indian-grouped digits with an ASCII "Rs " prefix, since
/// the pdf package's built-in fonts can't render the ₹ glyph (and we stay
/// offline — no Google-font fetch).
String pdfMoney(double v) => 'Rs ${Money.inr(v, symbol: false)}';

String formatInvoiceDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.gstRate,
    required this.lineTotal,
  });

  final String name;
  final int qty;
  final double unitPrice;
  final double gstRate;
  final double lineTotal;
}

class InvoiceData {
  const InvoiceData({
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.gstin,
    this.upiId,
    this.upiName,
    this.customerName,
    this.customerPhone,
    this.invoiceNumber,
    required this.date,
    required this.lines,
    required this.subtotal,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.grandTotal,
    required this.paid,
    required this.dues,
    this.upiUri,
  });

  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? gstin;
  final String? upiId;
  final String? upiName;
  final String? customerName;
  final String? customerPhone;
  final String? invoiceNumber;
  final DateTime date;
  final List<InvoiceLine> lines;
  final double subtotal;
  final double taxable;
  final double cgst;
  final double sgst;
  final double grandTotal;
  final double paid;
  final double dues;
  final String? upiUri;

  bool get hasGst => (gstin ?? '').trim().isNotEmpty;

  factory InvoiceData.fromOrder(
    Order order,
    BusinessProfile? profile, {
    String? overrideNumber,
  }) {
    final hasGst = (profile?.gstin ?? '').trim().isNotEmpty;
    double summedTaxable = 0;
    double tax = 0;
    final lines = <InvoiceLine>[];

    for (final it in order.items) {
      final lt = it.lineTotal;
      if (hasGst && it.gstRate > 0) {
        final base = lt / (1 + it.gstRate / 100);
        summedTaxable += base;
        tax += lt - base;
      } else {
        summedTaxable += lt;
      }
      lines.add(InvoiceLine(
        name: it.name,
        qty: it.qty,
        unitPrice: it.unitPrice,
        gstRate: it.gstRate,
        lineTotal: lt,
      ));
    }

    double round2(double v) => (v * 100).round() / 100;

    // Derive the GST components from a single rounded total and take the
    // taxable base as (grand total - tax), so subtotal + CGST + SGST always
    // reconciles to the printed grand total (no ±1 paise drift).
    final totalTax = hasGst ? round2(tax) : 0.0;
    final cgst = round2(totalTax / 2);
    final sgst = totalTax - cgst;
    final taxable =
        hasGst ? round2(order.grandTotal - totalTax) : round2(summedTaxable);

    final upiUri =
        (profile?.upiId != null && profile!.upiId!.isNotEmpty && order.dues > 0)
            ? buildUpiUri(
                vpa: profile.upiId!,
                name: profile.upiName,
                amount: order.dues,
                note: order.orderNumber != null
                    ? 'Order #${order.orderNumber}'
                    : 'Order',
              )
            : null;

    return InvoiceData(
      businessName: profile?.name ?? 'My Business',
      businessAddress: profile?.address,
      businessPhone: profile?.phone,
      gstin: hasGst ? profile!.gstin : null,
      upiId: profile?.upiId,
      upiName: profile?.upiName,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      invoiceNumber: overrideNumber ?? order.invoiceNumber,
      date: order.createdAt ?? DateTime.now(),
      lines: lines,
      subtotal: taxable,
      taxable: taxable,
      cgst: cgst,
      sgst: sgst,
      grandTotal: order.grandTotal,
      paid: order.paidTotal,
      dues: order.dues,
      upiUri: upiUri,
    );
  }
}
