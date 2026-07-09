# Invoice PDF (Stage 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate on-demand invoice PDFs from order data with three switchable templates (GST-optional, embedded UPI QR, share via WhatsApp), assign sequential invoice numbers, and add an Invoices tab.

**Architecture:** New `lib/features/invoices/` (data / pdf / controller / presentation). A `pdf`+`printing` pipeline turns an `Order` + `BusinessProfile` into an `InvoiceData` value, then into a `pw.Document` via a template registry (classic/minimal/boutique). `assign_invoice_number` RPC (migration 0014, invoker) hands out sequential numbers idempotently. `InvoiceShareScreen` previews + shares; a new bottom-nav tab lists invoiced orders.

**Tech Stack:** Flutter/Dart, Riverpod `StateNotifier`, Supabase RPC, `pdf` + `printing` (client-side PDF + `PdfPreview` share), `qr_flutter` (QR image for the PDF), existing design system.

---

## File Structure

**Database:**
- Create `supabase/migrations/0014_invoice_support.sql` — `invoice_template` column + `assign_invoice_number` RPC.

**New (client):**
- `lib/features/invoices/data/invoice_data.dart` — `InvoiceLine`, `InvoiceData` + `fromOrder`, `pdfMoney`/`formatInvoiceDate` helpers.
- `lib/features/invoices/data/invoice_service.dart` — `InvoiceService.assignInvoiceNumber`.
- `lib/features/invoices/pdf/classic.dart`, `minimal.dart`, `boutique.dart` — one `pw.Document` builder each.
- `lib/features/invoices/pdf/invoice_pdf.dart` — `InvoiceTemplate` enum + `buildInvoicePdf`.
- `lib/features/invoices/controller/invoice_provider.dart` — `invoiceServiceProvider` + `InvoiceController`.
- `lib/features/invoices/presentation/invoice_share_screen.dart` — chips + `PdfPreview`.
- `lib/features/invoices/presentation/invoices_screen.dart` — the Invoices tab.

**Modified (client):**
- `lib/features/orders/data/order.dart` — `Order.invoiceNumber`, `OrderItem.gstRate`.
- `lib/features/orders/presentation/order_detail_screen.dart` — "Share invoice" action.
- `lib/features/business/data/business_profile.dart` — `invoiceTemplate` field; drop server-managed fields from `toMap`.
- `lib/features/business/presentation/business_setup_screen.dart` — template dropdown; preserve numbering.
- `lib/main.dart` + `lib/shared/widgets/app_bottom_nav.dart` — 5th tab.
- `pubspec.yaml` — `pdf`, `printing`.

**Tests:**
- `test/features/invoices/invoice_data_test.dart`, `invoice_pdf_test.dart`, `invoice_controller_test.dart`, `invoice_share_screen_test.dart`, `invoices_screen_test.dart`.
- `test/features/orders/order_test.dart` — extend for `invoiceNumber`/`gstRate`.

---

### Task 1: Migration 0014 — invoice template + numbering RPC

**Files:**
- Create: `supabase/migrations/0014_invoice_support.sql`

Adds the per-business default template and an idempotent, ownership-checked invoice-number assigner.

- [ ] **Step 1: Write the migration**

```sql
-- Per-business default invoice template, and an idempotent sequential
-- invoice-number assigner. Invoker-scoped: touches only auth.uid()'s rows.

alter table public.business_profile
  add column invoice_template text not null default 'classic'
  check (invoice_template in ('classic', 'minimal', 'boutique'));

create or replace function public.assign_invoice_number(p_order_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_existing text;
  v_prefix text;
  v_next integer;
  v_number text;
begin
  select invoice_number into v_existing
  from orders where id = p_order_id and user_id = auth.uid();

  if not found then
    raise exception 'order_not_found';
  end if;

  -- Idempotent: never burn a second number for an already-invoiced order.
  if v_existing is not null then
    return v_existing;
  end if;

  select invoice_prefix, next_invoice_number into v_prefix, v_next
  from business_profile where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'business_profile_missing';
  end if;

  v_number := v_prefix || lpad(v_next::text, 4, '0');

  update orders set invoice_number = v_number
  where id = p_order_id and user_id = auth.uid();

  update business_profile set next_invoice_number = v_next + 1
  where user_id = auth.uid();

  return v_number;
end;
$$;

revoke all on function public.assign_invoice_number(uuid) from public, anon;
grant execute on function public.assign_invoice_number(uuid) to authenticated;
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `apply_migration` with `project_id: dgviploqkwyuttcdnddq`, `name: invoice_support`, and the SQL above. Expected: `{"success":true}`.

- [ ] **Step 3: Verify the function is invoker with a pinned search_path**

Use `execute_sql` (`project_id: dgviploqkwyuttcdnddq`):

```sql
select proname, prosecdef, proconfig
from pg_proc where proname = 'assign_invoice_number';
```

Expected: one row, `prosecdef = false`, `proconfig = {search_path=public}`.

- [ ] **Step 4: Advisors unchanged**

Use `get_advisors` (`type: security`). Expected: the same baseline (9 WARN + 1 INFO). `assign_invoice_number` is invoker, so it adds no `authenticated_security_definer` finding.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0014_invoice_support.sql
git commit -m "feat(db): invoice_template column and assign_invoice_number RPC"
```

---

### Task 2: Order.invoiceNumber + OrderItem.gstRate

**Files:**
- Modify: `lib/features/orders/data/order.dart`
- Test: `test/features/orders/order_test.dart`

The invoice needs the order's assigned number and each line's GST rate (the `order_items.gst_rate` snapshot the Stage 4 model never parsed).

- [ ] **Step 1: Add the failing tests**

Append these two tests inside `main()` in `test/features/orders/order_test.dart`:

```dart
  test('fromMap reads invoice_number and item gst_rate', () {
    final order = Order.fromMap({
      'id': 'o1',
      'invoice_number': 'INV-0042',
      'order_items': [
        {'name': 'Silk Saree', 'qty': 1, 'unit_price': '2500', 'gst_rate': '5'},
      ],
    });
    expect(order.invoiceNumber, 'INV-0042');
    expect(order.items.single.gstRate, 5);
  });

  test('invoiceNumber is null and gstRate defaults to 0 when absent', () {
    final order = Order.fromMap({'id': 'o2', 'order_items': [
      {'name': 'X', 'qty': 1},
    ]});
    expect(order.invoiceNumber, isNull);
    expect(order.items.single.gstRate, 0);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/orders/order_test.dart`
Expected: FAIL — `Order` has no `invoiceNumber`, `OrderItem` no `gstRate`.

- [ ] **Step 3: Extend OrderItem**

In `lib/features/orders/data/order.dart`, add `this.gstRate = 0,` to the `OrderItem` constructor (after `this.lineTotal = 0,`), add the field after `final double lineTotal;`:

```dart
  final double lineTotal;
  final double gstRate;
```

and in `OrderItem.fromMap` add (after the `lineTotal:` line):

```dart
      lineTotal: double.tryParse(map['line_total']?.toString() ?? '') ?? 0,
      gstRate: double.tryParse(map['gst_rate']?.toString() ?? '') ?? 0,
```

- [ ] **Step 4: Extend Order**

Add `this.invoiceNumber,` to the `Order` constructor (after `this.orderNumber,`), the field after `final int? orderNumber;`:

```dart
  final int? orderNumber;
  final String? invoiceNumber;
```

and in `Order.fromMap` add (after the `orderNumber:` line):

```dart
      orderNumber: int.tryParse(map['order_number']?.toString() ?? ''),
      invoiceNumber: map['invoice_number']?.toString(),
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/orders/order_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/orders/data/order.dart test/features/orders/order_test.dart
git commit -m "feat(orders): Order.invoiceNumber and OrderItem.gstRate"
```

---

### Task 3: BusinessProfile.invoiceTemplate + numbering-safe toMap

**Files:**
- Modify: `lib/features/business/data/business_profile.dart`
- Test: `test/features/business/business_profile_test.dart`

Adds the default-template field and stops the client from overwriting the server-managed `invoice_prefix`/`next_invoice_number` on upsert (a plain re-save of business setup currently rebuilds the profile from scratch and would reset the counter to 1).

- [ ] **Step 1: Write the failing test**

Create `test/features/business/business_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';

void main() {
  test('fromMap reads invoice_template, defaults to classic', () {
    expect(
      BusinessProfile.fromMap({'name': 'S', 'invoice_template': 'boutique'})
          .invoiceTemplate,
      'boutique',
    );
    expect(
      BusinessProfile.fromMap({'name': 'S'}).invoiceTemplate,
      'classic',
    );
  });

  test('toMap omits server-managed numbering fields but keeps template', () {
    final map = const BusinessProfile(name: 'S', invoiceTemplate: 'minimal').toMap();
    expect(map.containsKey('next_invoice_number'), isFalse);
    expect(map.containsKey('invoice_prefix'), isFalse);
    expect(map['invoice_template'], 'minimal');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: FAIL — no `invoiceTemplate`; `toMap` still has the numbering keys.

- [ ] **Step 3: Add the field**

In `lib/features/business/data/business_profile.dart`, add `this.invoiceTemplate = 'classic',` to the constructor (after `this.currency = 'INR',`) and the field after `final String currency;`:

```dart
  final String currency;
  final String invoiceTemplate;
```

In `fromMap`, add (after the `currency:` line):

```dart
      currency: (map['currency'] ?? 'INR').toString(),
      invoiceTemplate: (map['invoice_template'] ?? 'classic').toString(),
```

- [ ] **Step 4: Fix toMap (drop server-managed fields, add template)**

Replace the `toMap()` method body's map so it no longer sends `invoice_prefix`/`next_invoice_number` (the DB owns these — defaulted on insert, bumped only by `assign_invoice_number`) and adds `invoice_template`:

```dart
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'logo_url': logoUrl,
        'address': address,
        'phone': phone,
        'email': email,
        'upi_id': upiId,
        'upi_name': upiName,
        'gstin': gstin,
        'default_gst_rate': defaultGstRate,
        'currency': currency,
        'invoice_template': invoiceTemplate,
      };
```

- [ ] **Step 5: Thread invoiceTemplate through copyWith**

In `copyWith`, add `String? invoiceTemplate,` to the parameter list and `invoiceTemplate: invoiceTemplate ?? this.invoiceTemplate,` to the returned `BusinessProfile(...)`.

- [ ] **Step 6: Run to verify pass**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/business/data/business_profile.dart test/features/business/business_profile_test.dart
git commit -m "feat(business): invoiceTemplate field; stop client resetting invoice counter"
```

---

### Task 4: InvoiceData + GST extraction

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/invoices/data/invoice_data.dart`
- Test: `test/features/invoices/invoice_data_test.dart`

Pure value type computed from an `Order` + `BusinessProfile`, with tax-inclusive GST extraction that only applies when the business has a GSTIN.

- [ ] **Step 1: Add pdf + printing deps**

In `pubspec.yaml`, under `dependencies:` (next to `qr_flutter: ^4.1.0`), add:

```yaml
  pdf: ^3.11.1
  printing: ^5.13.1
```

Run: `flutter pub get`
Expected: resolves without conflict.

- [ ] **Step 2: Write the failing tests**

Create `test/features/invoices/invoice_data_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/data/invoice_data.dart';

void main() {
  Order order({String? gstRate}) => Order.fromMap({
        'id': 'o1',
        'invoice_number': 'INV-0001',
        'order_number': 1,
        'grand_total': '5250',
        'customers': {'name': 'Priya', 'phone': '9876543210'},
        'created_at': '2026-07-08T00:00:00Z',
        'order_items': [
          {'name': 'Saree', 'qty': 1, 'unit_price': '5250', 'line_total': '5250',
           if (gstRate != null) 'gst_rate': gstRate},
        ],
        'payments': [
          {'amount': '2000'},
        ],
      });

  test('no GSTIN: no tax, subtotal equals grand total', () {
    final d = InvoiceData.fromOrder(order(gstRate: '5'),
        const BusinessProfile(name: 'Shop')); // no gstin
    expect(d.hasGst, isFalse);
    expect(d.cgst, 0);
    expect(d.sgst, 0);
    expect(d.subtotal, 5250);
    expect(d.grandTotal, 5250);
  });

  test('with GSTIN: tax extracted inclusive, total unchanged', () {
    final d = InvoiceData.fromOrder(order(gstRate: '5'),
        const BusinessProfile(name: 'Shop', gstin: '29ABCDE1234F1Z5'));
    expect(d.hasGst, isTrue);
    // 5250 inclusive of 5% => taxable 5000, tax 250, split 125/125.
    expect(d.taxable, closeTo(5000, 0.01));
    expect(d.cgst, closeTo(125, 0.01));
    expect(d.sgst, closeTo(125, 0.01));
    expect(d.grandTotal, 5250);
  });

  test('carries paid/dues, number, customer and upi', () {
    final d = InvoiceData.fromOrder(order(),
        const BusinessProfile(name: 'Shop', upiId: 'shop@upi', upiName: 'Shop'));
    expect(d.invoiceNumber, 'INV-0001');
    expect(d.paid, 2000);
    expect(d.dues, 3250);
    expect(d.customerName, 'Priya');
    expect(d.upiUri, contains('pa=shop@upi'));
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/features/invoices/invoice_data_test.dart`
Expected: FAIL — `invoice_data.dart` does not exist.

- [ ] **Step 4: Implement InvoiceData**

Create `lib/features/invoices/data/invoice_data.dart`:

```dart
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

  factory InvoiceData.fromOrder(Order order, BusinessProfile? profile) {
    final hasGst = (profile?.gstin ?? '').trim().isNotEmpty;
    double taxable = 0;
    double tax = 0;
    final lines = <InvoiceLine>[];

    for (final it in order.items) {
      final lt = it.lineTotal;
      if (hasGst && it.gstRate > 0) {
        final base = lt / (1 + it.gstRate / 100);
        taxable += base;
        tax += lt - base;
      } else {
        taxable += lt;
      }
      lines.add(InvoiceLine(
        name: it.name,
        qty: it.qty,
        unitPrice: it.unitPrice,
        gstRate: it.gstRate,
        lineTotal: lt,
      ));
    }

    final round2 = (double v) => (v * 100).round() / 100;
    final half = round2(tax / 2);

    final upiUri = (profile?.upiId != null && profile!.upiId!.isNotEmpty)
        ? buildUpiUri(
            vpa: profile.upiId!,
            name: profile.upiName,
            amount: order.dues,
            note: order.orderNumber != null ? 'Order #${order.orderNumber}' : 'Order',
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
      invoiceNumber: order.invoiceNumber,
      date: order.createdAt ?? DateTime.now(),
      lines: lines,
      subtotal: round2(taxable),
      taxable: round2(taxable),
      cgst: hasGst ? half : 0,
      sgst: hasGst ? half : 0,
      grandTotal: order.grandTotal,
      paid: order.paidTotal,
      dues: order.dues,
      upiUri: upiUri,
    );
  }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/invoices/invoice_data_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/invoices/data/invoice_data.dart test/features/invoices/invoice_data_test.dart
git commit -m "feat(invoices): InvoiceData with tax-inclusive GST extraction"
```

---

### Task 5: PDF templates + registry

**Files:**
- Create: `lib/features/invoices/pdf/classic.dart`, `minimal.dart`, `boutique.dart`, `invoice_pdf.dart`
- Test: `test/features/invoices/invoice_pdf_test.dart`

Three `pw.Document` builders sharing `InvoiceData`, and an async `buildInvoicePdf` that renders the UPI QR to a PNG and dispatches by template.

- [ ] **Step 1: Write the failing smoke tests**

Create `test/features/invoices/invoice_pdf_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/invoices/data/invoice_data.dart';
import 'package:orderly_app/features/invoices/pdf/invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InvoiceData data({bool gst = false, bool paidFull = false, String? upi}) =>
      InvoiceData(
        businessName: 'Rekha Boutique',
        businessPhone: '9876543210',
        gstin: gst ? '29ABCDE1234F1Z5' : null,
        upiId: upi,
        upiName: 'Rekha',
        customerName: 'Priya',
        invoiceNumber: 'INV-0001',
        date: DateTime(2026, 7, 8),
        lines: const [
          InvoiceLine(name: 'Silk Saree', qty: 2, unitPrice: 2500, gstRate: 5, lineTotal: 5000),
        ],
        subtotal: 5000,
        taxable: gst ? 4761.90 : 5000,
        cgst: gst ? 119.05 : 0,
        sgst: gst ? 119.05 : 0,
        grandTotal: 5000,
        paid: paidFull ? 5000 : 2000,
        dues: paidFull ? 0 : 3000,
        upiUri: upi == null ? null : 'upi://pay?pa=$upi&am=3000.00&cu=INR',
      );

  for (final t in InvoiceTemplate.values) {
    test('buildInvoicePdf $t produces non-empty bytes across variants', () async {
      for (final d in [
        data(),
        data(gst: true),
        data(paidFull: true),
        data(upi: 'rekha@upi'),
        data(gst: true, upi: 'rekha@upi'),
      ]) {
        final bytes = await buildInvoicePdf(d, t);
        expect(bytes, isNotEmpty);
      }
    });
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/invoices/invoice_pdf_test.dart`
Expected: FAIL — pdf files don't exist.

- [ ] **Step 3: Implement the registry (`invoice_pdf.dart`)**

Create `lib/features/invoices/pdf/invoice_pdf.dart`:

```dart
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
```

- [ ] **Step 4: Implement the Classic template (`classic.dart`)**

Create `lib/features/invoices/pdf/classic.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
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
                  l.name,
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
```

- [ ] **Step 5: Implement the Minimal template (`minimal.dart`)**

Create `lib/features/invoices/pdf/minimal.dart`:

```dart
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
                  pw.Expanded(child: pw.Text('${l.name}   ${l.qty} x ${pdfMoney(l.unitPrice)}')),
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
```

- [ ] **Step 6: Implement the Boutique template (`boutique.dart`)**

Create `lib/features/invoices/pdf/boutique.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/invoice_data.dart';

const _accent = PdfColor.fromInt(0xFF6C4ED9);

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
```

- [ ] **Step 7: Run to verify pass**

Run: `flutter test test/features/invoices/invoice_pdf_test.dart`
Expected: PASS (3 template groups). If `toImageData` throws in the headless test, confirm `TestWidgetsFlutterBinding.ensureInitialized()` is the first line of `main()`.

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze lib/features/invoices/pdf`
Expected: No issues.

```bash
git add lib/features/invoices/pdf test/features/invoices/invoice_pdf_test.dart
git commit -m "feat(invoices): classic/minimal/boutique PDF templates and registry"
```

---

### Task 6: InvoiceService + InvoiceController

**Files:**
- Create: `lib/features/invoices/data/invoice_service.dart`
- Create: `lib/features/invoices/controller/invoice_provider.dart`
- Test: `test/features/invoices/invoice_controller_test.dart`

Thin RPC client + an auth-scoped controller that assigns the number once and reloads orders.

- [ ] **Step 1: Write the failing tests**

Create `test/features/invoices/invoice_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/controller/invoice_provider.dart';
import 'package:orderly_app/features/invoices/data/invoice_service.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

class FakeInvoiceService implements InvoiceService {
  int calls = 0;
  bool throwNext = false;
  @override
  Future<String> assignInvoiceNumber(String orderId) async {
    calls++;
    if (throwNext) throw Exception('boom');
    return 'INV-0001';
  }
}

void main() {
  test('prepare assigns a number and reloads orders', () async {
    final inv = FakeInvoiceService();
    final orders = FakeOrdersService(const [Order(id: 'o1')]);
    final c = ProviderContainer(overrides: [
      invoiceServiceProvider.overrideWithValue(inv),
      ordersServiceProvider.overrideWithValue(orders),
    ]);
    addTearDown(c.dispose);

    final number = await c.read(invoiceControllerProvider.notifier)
        .prepare(const Order(id: 'o1'));

    expect(number, 'INV-0001');
    expect(inv.calls, 1);
  });

  test('prepare returns null on failure', () async {
    final inv = FakeInvoiceService()..throwNext = true;
    final orders = FakeOrdersService(const []);
    final c = ProviderContainer(overrides: [
      invoiceServiceProvider.overrideWithValue(inv),
      ordersServiceProvider.overrideWithValue(orders),
    ]);
    addTearDown(c.dispose);

    final number = await c.read(invoiceControllerProvider.notifier)
        .prepare(const Order(id: 'o1'));

    expect(number, isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/invoices/invoice_controller_test.dart`
Expected: FAIL — service/provider don't exist.

- [ ] **Step 3: Implement the service**

Create `lib/features/invoices/data/invoice_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class InvoiceService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> assignInvoiceNumber(String orderId) async {
    final res = await _client
        .rpc('assign_invoice_number', params: {'p_order_id': orderId});
    return res.toString();
  }
}
```

- [ ] **Step 4: Implement the provider + controller**

Create `lib/features/invoices/controller/invoice_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';

import '../data/invoice_service.dart';

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return InvoiceService();
});

final invoiceControllerProvider =
    StateNotifierProvider<InvoiceController, AsyncValue<void>>((ref) {
  return InvoiceController(ref.watch(invoiceServiceProvider), ref);
});

class InvoiceController extends StateNotifier<AsyncValue<void>> {
  InvoiceController(this._service, this._ref)
      : super(const AsyncValue.data(null));

  final InvoiceService _service;
  final Ref _ref;

  /// Assigns (idempotently) and returns the order's invoice number, then
  /// reloads orders so the order carries it. Returns null on failure.
  Future<String?> prepare(Order order) async {
    state = const AsyncValue.loading();
    final res =
        await AsyncValue.guard(() => _service.assignInvoiceNumber(order.id!));
    if (res.hasError) {
      state = AsyncValue.error(res.error!, res.stackTrace!);
      return null;
    }
    state = const AsyncValue.data(null);
    await _ref.read(ordersControllerProvider.notifier).load();
    return res.value;
  }
}
```

Note: `authUserIdProvider` is re-exported by `orders_provider.dart` (Stage 4), so importing `orders_provider.dart` supplies it — do not add a separate `auth_providers.dart` import (it triggers an `unnecessary_import` lint).

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/invoices/invoice_controller_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/invoices/data/invoice_service.dart lib/features/invoices/controller/invoice_provider.dart test/features/invoices/invoice_controller_test.dart
git commit -m "feat(invoices): InvoiceService and InvoiceController.prepare"
```

---

### Task 7: InvoiceShareScreen

**Files:**
- Create: `lib/features/invoices/presentation/invoice_share_screen.dart`
- Test: `test/features/invoices/invoice_share_screen_test.dart`

Assigns the number on open, shows template chips (default from the profile) and a `PdfPreview` (its toolbar shares to the OS sheet). Switching a chip re-renders.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/invoices/invoice_share_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/controller/invoice_provider.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_share_screen.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;
import 'invoice_controller_test.dart' show FakeInvoiceService;

void main() {
  testWidgets('renders template chips with the profile default preselected',
      (tester) async {
    final order = Order.fromMap({
      'id': 'o1', 'order_number': 1, 'invoice_number': 'INV-0001',
      'grand_total': '5000',
      'order_items': [
        {'name': 'Saree', 'qty': 1, 'unit_price': '5000', 'line_total': '5000'},
      ],
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        invoiceServiceProvider.overrideWithValue(FakeInvoiceService()),
        ordersServiceProvider.overrideWithValue(FakeOrdersService([order])),
        businessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(name: 'Shop', invoiceTemplate: 'minimal')),
      ],
      child: MaterialApp(home: InvoiceShareScreen(order: order)),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
    expect(find.text('Boutique'), findsOneWidget);

    // Default 'minimal' selected.
    final minimal = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Minimal'));
    expect(minimal.selected, isTrue);

    await tester.tap(find.text('Classic'));
    await tester.pump(const Duration(milliseconds: 200));
    final classic = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Classic'));
    expect(classic.selected, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/invoices/invoice_share_screen_test.dart`
Expected: FAIL — screen doesn't exist.

- [ ] **Step 3: Implement the screen**

Create `lib/features/invoices/presentation/invoice_share_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:printing/printing.dart';

import '../controller/invoice_provider.dart';
import '../data/invoice_data.dart';
import '../pdf/invoice_pdf.dart';

class InvoiceShareScreen extends ConsumerStatefulWidget {
  const InvoiceShareScreen({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<InvoiceShareScreen> createState() => _InvoiceShareScreenState();
}

class _InvoiceShareScreenState extends ConsumerState<InvoiceShareScreen> {
  InvoiceTemplate? _template;
  bool _preparing = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepare);
  }

  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _failed = false;
    });
    final number =
        await ref.read(invoiceControllerProvider.notifier).prepare(widget.order);
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _failed = number == null;
    });
  }

  Order get _live => ref
          .watch(ordersControllerProvider)
          .valueOrNull
          ?.where((o) => o.id == widget.order.id)
          .firstOrNull ??
      widget.order;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final template = _template ?? invoiceTemplateFromKey(profile?.invoiceTemplate);
    final order = _live;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order.invoiceNumber != null
            ? 'Invoice ${order.invoiceNumber}'
            : 'Invoice'),
      ),
      body: _preparing
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not prepare the invoice'),
                      TextButton(onPressed: _prepare, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        children: [
                          for (final t in InvoiceTemplate.values)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: AppSpacing.sm),
                              child: ChoiceChip(
                                label: Text(invoiceTemplateLabel(t)),
                                selected: template == t,
                                onSelected: (_) =>
                                    setState(() => _template = t),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PdfPreview(
                        key: ValueKey(template),
                        build: (format) => buildInvoicePdf(
                          InvoiceData.fromOrder(order, profile),
                          template,
                        ),
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                      ),
                    ),
                  ],
                ),
    );
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/invoices/invoice_share_screen_test.dart`
Expected: PASS. (The `PdfPreview` renders asynchronously; the test only asserts chip state, using `pump` with a fixed duration rather than `pumpAndSettle`.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/invoices/presentation/invoice_share_screen.dart test/features/invoices/invoice_share_screen_test.dart
git commit -m "feat(invoices): invoice share screen with template switch and PDF preview"
```

---

### Task 8: Invoices tab (screen + 5th nav item)

**Files:**
- Create: `lib/features/invoices/presentation/invoices_screen.dart`
- Modify: `lib/main.dart`, `lib/shared/widgets/app_bottom_nav.dart`
- Test: `test/features/invoices/invoices_screen_test.dart`

Lists invoiced orders (derived from `ordersControllerProvider`), and wires a 5th bottom-nav tab.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/invoices/invoices_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

void main() {
  Widget wrap(List<Order> orders) => ProviderScope(
        overrides: [
          ordersServiceProvider.overrideWithValue(FakeOrdersService(orders)),
        ],
        child: const MaterialApp(home: InvoicesScreen()),
      );

  testWidgets('lists only invoiced orders', (tester) async {
    await tester.pumpWidget(wrap(const [
      Order(id: 'o1', orderNumber: 1, invoiceNumber: 'INV-0001', customerName: 'Priya'),
      Order(id: 'o2', orderNumber: 2, customerName: 'Anita'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('INV-0001'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('shows empty state when nothing is invoiced', (tester) async {
    await tester.pumpWidget(wrap(const [Order(id: 'o1', customerName: 'Anita')]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No invoices yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/invoices/invoices_screen_test.dart`
Expected: FAIL — screen doesn't exist.

- [ ] **Step 3: Implement InvoicesScreen**

Create `lib/features/invoices/presentation/invoices_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

import 'invoice_share_screen.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ordersControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text('Invoices',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(ordersControllerProvider.notifier).load(),
                    child: const Text('Retry'),
                  ),
                ),
                data: (orders) {
                  final invoiced = orders
                      .where((o) => o.invoiceNumber != null)
                      .toList();
                  if (invoiced.isEmpty) {
                    return const Center(
                      child: Text(
                        'No invoices yet.\nShare an invoice from an order to see it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(ordersControllerProvider.notifier).load(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, 96),
                      itemCount: invoiced.length,
                      itemBuilder: (context, i) {
                        final o = invoiced[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      InvoiceShareScreen(order: o)),
                            ),
                            child: AppCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(o.invoiceNumber!,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textPrimary)),
                                        const SizedBox(height: 2),
                                        Text(o.customerName ?? 'Customer',
                                            style: const TextStyle(
                                                color:
                                                    AppColors.textSecondary,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(Money.inr(o.grandTotal),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary)),
                                      const SizedBox(height: 4),
                                      StatusPill(status: o.paymentStatus),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the screen test**

Run: `flutter test test/features/invoices/invoices_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the 5th nav item**

In `lib/shared/widgets/app_bottom_nav.dart`, add a fifth item to the `Row` children (after the Catalog item at index 3):

```dart
            Expanded(child: navItem(Icons.storefront_rounded, "Catalog", 3)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.receipt_long_rounded, "Invoices", 4)),
```

- [ ] **Step 6: Wire the tab into MainScreen**

In `lib/main.dart`, add the import near the other feature screen imports:

```dart
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';
```

Add `const InvoicesScreen(),` to the `_screens` list (after `const CatalogScreen(),`):

```dart
    _screens = [
      DashboardScreen(onNavigate: changeTab),
      const EnquiriesScreen(),
      OrdersScreen(),
      const CatalogScreen(),
      const InvoicesScreen(),
    ];
```

Hide the FAB on the Invoices tab: replace the `floatingActionButton:` line with a conditional so it's null on index 4:

```dart
      floatingActionButton: currentIndex == 4
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () {
                if (currentIndex == 3) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CaptureScreen()),
                );
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
```

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/main.dart lib/shared/widgets/app_bottom_nav.dart lib/features/invoices`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/invoices/presentation/invoices_screen.dart lib/main.dart lib/shared/widgets/app_bottom_nav.dart test/features/invoices/invoices_screen_test.dart
git commit -m "feat(invoices): Invoices tab and fifth bottom-nav item"
```

---

### Task 9: Wire entry points (order detail + business setup)

**Files:**
- Modify: `lib/features/orders/presentation/order_detail_screen.dart`
- Modify: `lib/features/business/presentation/business_setup_screen.dart`

A "Share invoice" button on the order and a template dropdown in setup.

- [ ] **Step 1: Add the Share-invoice action to the order detail**

In `lib/features/orders/presentation/order_detail_screen.dart`, add the import (with the other invoice/payments imports):

```dart
import 'package:orderly_app/features/invoices/presentation/invoice_share_screen.dart';
```

In `build`, add a "Share invoice" button right after the payment `AppCard` closes (before the `if (order.courier != null ...` block), so it is always available once an order exists:

```dart
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => InvoiceShareScreen(order: order)),
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Share invoice'),
          ),
```

- [ ] **Step 2: Add the template dropdown to business setup**

In `lib/features/business/presentation/business_setup_screen.dart`, add a state field for the chosen template near the controllers:

```dart
  String _template = 'classic';
```

Preload it (and preserve numbering) — add an `initState` that seeds from the existing profile:

```dart
  @override
  void initState() {
    super.initState();
    final existing = ref.read(businessProfileProvider).valueOrNull;
    if (existing != null) _template = existing.invoiceTemplate;
  }
```

Add the dropdown to the form `children` (after the `_field(_gstRate, ...)` line):

```dart
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _template,
              decoration: InputDecoration(
                labelText: 'Invoice template',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'classic', child: Text('Classic')),
                DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                DropdownMenuItem(value: 'boutique', child: Text('Boutique')),
              ],
              onChanged: (v) => setState(() => _template = v ?? 'classic'),
            ),
```

Thread `_template` into the saved profile — in `_save`, add `invoiceTemplate: _template,` to the `BusinessProfile(...)` constructor call.

- [ ] **Step 3: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Full test suite**

Run: `flutter test`
Expected: all pass (prior suites + the new invoices tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/presentation/order_detail_screen.dart lib/features/business/presentation/business_setup_screen.dart
git commit -m "feat(invoices): share-invoice entry point and business-setup template dropdown"
```

---

### Task 10: Final gate + review

**Files:** none (verification + review).

- [ ] **Step 1: Full analyze + tests**

Run: `flutter analyze` (expect `No issues found!`) then `flutter test` (expect all green).

- [ ] **Step 2: Advisors unchanged**

Use the Supabase MCP `get_advisors` (`type: security`). Expected: the same baseline (9 WARN + 1 INFO); no new finding.

- [ ] **Step 3: Final code review**

Dispatch the code-reviewer agent over the whole slice (`git diff <Task-1-commit>^..HEAD -- supabase lib test pubspec.yaml`). Focus: `assign_invoice_number` ownership + invoker scoping + idempotency (never burns two numbers, the `for update` lock); the `toMap` change truly stops the client from resetting `next_invoice_number` (and no other caller depended on those keys); GST extraction correctness (tax-inclusive, total unchanged, no double-count when `gst_rate` is 0); the PDF money helper avoids the ₹ glyph; no untrusted input in the UPI/QR; template registry has no missing case; the 5-tab nav indices/FAB conditional are consistent. Fix verified findings and re-review.

- [ ] **Step 4: Finish the branch**

Use superpowers:finishing-a-development-branch. Then deliver a summary + device smoke checklist: open a paid/delivered order → Share invoice → `INV-0001` assigned → switch Classic/Minimal/Boutique → GST lines only when a GSTIN is set → share to WhatsApp as a PDF → the order appears under the Invoices tab → reopening shows the same number → re-saving Business setup does NOT reset the next number.

---

## Self-Review

**1. Spec coverage:**
- Typed Invoices feature data/pdf/controller/presentation (§3) → Tasks 4–8.
- Three templates + registry, switchable, default on profile (§2.2, §7) → Task 5 (registry/builders) + Task 7 (switch) + Task 9 (default dropdown).
- Sequential number assigned once, stored on order (§2.3, §6) → Task 1 RPC + Task 2 model + Task 6 controller.
- GST optional, tax-inclusive, total unchanged (§2.4, §5) → Task 4 `fromOrder`.
- UPI QR embedded + share via OS sheet (§2.5, §7) → Task 5 QR render + Task 7 `PdfPreview`.
- Invoices tab (§2.6, §7) → Task 8.
- Non-goals honored: no storage (PDF is in-memory), no logo embed (name text only), no IGST, no template editing.
- Security (§9): invoker + ownership + `for update` + revokes (Task 1); client no longer overwrites numbering (Task 3).

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to". Every code step is complete and pastable as-is (the `_months` constant is the correct 12-entry list). No conditional or placeholder remains.

**3. Type consistency:** `InvoiceData`/`InvoiceLine` fields (Task 4) are consumed identically by the three templates (Task 5) and `InvoiceData.fromOrder` in the share screen (Task 7). `buildInvoicePdf(InvoiceData, InvoiceTemplate)` and the `classicDoc`/`minimalDoc`/`boutiqueDoc` signatures `(InvoiceData, Uint8List?)` match across Task 5 files. `InvoiceService.assignInvoiceNumber(String) -> Future<String>` (Task 6) matches `FakeInvoiceService`, the controller, and the share screen. `invoiceServiceProvider`/`invoiceControllerProvider`/`InvoiceController.prepare(Order) -> Future<String?>` (Task 6) are used consistently in Task 7. `invoiceTemplateFromKey`/`invoiceTemplateLabel`/`InvoiceTemplate` (Task 5) are used in Task 7. `Order.invoiceNumber`/`OrderItem.gstRate` (Task 2) and `BusinessProfile.invoiceTemplate` (Task 3) are read in Tasks 4/7/8/9. `authUserIdProvider` re-export reused (Task 6 note). Nav indices: Catalog=3, Invoices=4, FAB null on 4 (Task 8) — consistent.
```
