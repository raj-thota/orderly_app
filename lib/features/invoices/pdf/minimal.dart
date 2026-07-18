import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/invoice_data.dart';

pw.Document minimalDoc(InvoiceData d, Uint8List? qr) {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(d.businessName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(d.hasGst
                  ? 'Tax Invoice ${d.invoiceNumber ?? ''}'
                  : 'Invoice ${d.invoiceNumber ?? ''}'),
              pw.Text(formatInvoiceDate(d.date)),
            ],
          ),
          if (d.customerName != null) ...[
            pw.SizedBox(height: 12),
            pw.Text('Bill to  ${d.customerName}',
                style: pw.TextStyle(color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 16),
          for (final l in d.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text('${l.displayName}   ${l.qty} x ${pdfMoney(l.unitPrice)}')),
                  pw.Text(pdfMoney(l.lineTotal)),
                ],
              ),
            ),
          pw.Divider(),
          _row('Subtotal', pdfMoney(d.subtotal)),
          if (d.hasGst) _row('CGST', pdfMoney(d.cgst)),
          if (d.hasGst) _row('SGST', pdfMoney(d.sgst)),
          _row('Total', pdfMoney(d.grandTotal), bold: true),
          _row('Paid', pdfMoney(d.paid)),
          _row('Dues', pdfMoney(d.dues)),
          pw.SizedBox(height: 20),
          if (qr != null)
            pw.Row(children: [
              pw.Image(pw.MemoryImage(qr), width: 80, height: 80),
              pw.SizedBox(width: 8),
              if (d.upiId != null) pw.Text('Pay ${d.upiId}'),
            ]),
        ],
      ),
    ),
  );
  return doc;
}

pw.Widget _row(String label, String value, {bool bold = false}) {
  final style = bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null;
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [pw.Text(label, style: style), pw.Text(value, style: style)],
  );
}
