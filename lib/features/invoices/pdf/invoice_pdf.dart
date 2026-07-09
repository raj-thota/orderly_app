import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../data/invoice_data.dart';
import 'boutique.dart';
import 'classic.dart';
import 'minimal.dart';

enum InvoiceTemplate { classic, minimal, boutique }

InvoiceTemplate invoiceTemplateFromKey(String? key) {
  switch (key) {
    case 'minimal':
      return InvoiceTemplate.minimal;
    case 'boutique':
      return InvoiceTemplate.boutique;
    default:
      return InvoiceTemplate.classic;
  }
}

String invoiceTemplateLabel(InvoiceTemplate t) {
  switch (t) {
    case InvoiceTemplate.classic:
      return 'Classic';
    case InvoiceTemplate.minimal:
      return 'Minimal';
    case InvoiceTemplate.boutique:
      return 'Boutique';
  }
}

Future<Uint8List?> _renderQr(String? uri) async {
  if (uri == null || uri.isEmpty) return null;
  final painter = QrPainter(
    data: uri,
    version: QrVersions.auto,
    gapless: true,
  );
  final bytes = await painter.toImageData(400);
  return bytes?.buffer.asUint8List();
}

Future<Uint8List> buildInvoicePdf(
  InvoiceData data,
  InvoiceTemplate template,
) async {
  final qr = await _renderQr(data.upiUri);
  final pw.Document doc;
  switch (template) {
    case InvoiceTemplate.classic:
      doc = classicDoc(data, qr);
      break;
    case InvoiceTemplate.minimal:
      doc = minimalDoc(data, qr);
      break;
    case InvoiceTemplate.boutique:
      doc = boutiqueDoc(data, qr);
      break;
  }
  return doc.save();
}
