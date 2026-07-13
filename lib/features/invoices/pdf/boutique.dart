import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/invoice_data.dart';

// Keep in sync with AppColors.primary (pdf package can't use Flutter colors).
const _accent = PdfColor.fromInt(0xFF5B4FE9);

pw.Document boutiqueDoc(InvoiceData d, Uint8List? qr) {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            color: _accent,
            padding: const pw.EdgeInsets.all(24),
            child: pw.Center(
              child: pw.Text(
                d.businessName.toUpperCase(),
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        (d.hasGst ? 'Tax Invoice ' : 'Invoice ') +
                            (d.invoiceNumber ?? ''),
                        style: pw.TextStyle(
                            color: _accent, fontWeight: pw.FontWeight.bold)),
                    pw.Text(formatInvoiceDate(d.date)),
                  ],
                ),
                if (d.customerName != null) pw.Text('For ${d.customerName}'),
                if (d.hasGst) pw.Text('GSTIN: ${d.gstin}'),
                pw.SizedBox(height: 16),
                for (final l in d.lines)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text('${l.name}  x${l.qty}')),
                        pw.Text(pdfMoney(l.lineTotal)),
                      ],
                    ),
                  ),
                pw.Divider(color: _accent),
                if (d.hasGst) _row('CGST', pdfMoney(d.cgst)),
                if (d.hasGst) _row('SGST', pdfMoney(d.sgst)),
                _row('TOTAL', pdfMoney(d.grandTotal), bold: true),
                _row('Paid', pdfMoney(d.paid)),
                _row('Dues', pdfMoney(d.dues), bold: true),
                pw.SizedBox(height: 18),
                if (qr != null)
                  pw.Row(children: [
                    pw.Image(pw.MemoryImage(qr), width: 90, height: 90),
                    pw.SizedBox(width: 10),
                    if (d.upiId != null)
                      pw.Text(d.upiId!, style: pw.TextStyle(color: _accent)),
                  ]),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc;
}

pw.Widget _row(String label, String value, {bool bold = false}) {
  final style = bold
      ? pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _accent)
      : null;
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [pw.Text(label, style: style), pw.Text(value, style: style)],
  );
}
