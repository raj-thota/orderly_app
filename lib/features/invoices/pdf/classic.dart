import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../data/invoice_data.dart';

pw.Document classicDoc(InvoiceData d, Uint8List? qr) {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(d.businessName,
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (d.businessAddress != null) pw.Text(d.businessAddress!),
                  if (d.businessPhone != null) pw.Text('Ph: ${d.businessPhone}'),
                  if (d.hasGst) pw.Text('GSTIN: ${d.gstin}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(d.hasGst ? 'TAX INVOICE' : 'INVOICE',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  if (d.invoiceNumber != null) pw.Text(d.invoiceNumber!),
                  pw.Text(formatInvoiceDate(d.date)),
                ],
              ),
            ],
          ),
          pw.Divider(),
          if (d.customerName != null)
            pw.Text('Bill to: ${d.customerName}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Rate', 'Amount'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: [
              for (final l in d.lines)
                [
                  l.displayName,
                  '${l.qty}',
                  pdfMoney(l.unitPrice),
                  pdfMoney(l.lineTotal),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(children: [
                _row('Subtotal', pdfMoney(d.subtotal)),
                if (d.hasGst) _row('CGST', pdfMoney(d.cgst)),
                if (d.hasGst) _row('SGST', pdfMoney(d.sgst)),
                pw.Divider(),
                _row('Total', pdfMoney(d.grandTotal), bold: true),
                _row('Paid', pdfMoney(d.paid)),
                _row('Dues', pdfMoney(d.dues), bold: true),
              ]),
            ),
          ),
          pw.SizedBox(height: 16),
          if (qr != null)
            pw.Row(children: [
              pw.Image(pw.MemoryImage(qr), width: 90, height: 90),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('Scan to pay via UPI'),
                  if (d.upiId != null) pw.Text(d.upiId!),
                ],
              ),
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
