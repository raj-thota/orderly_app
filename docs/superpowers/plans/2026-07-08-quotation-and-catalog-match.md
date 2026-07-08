# Slice D (trimmed) — Quotation + Catalog Match Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From a capture draft's items, build a plain-text quotation (business name, line items, total, UPI) — enriching prices by fuzzy-matching the catalog — preview it, share it on WhatsApp on explicit tap, and record the sent quote as an activity on the enquiry.

**Architecture:** A small pure `quotations` data unit does the two testable jobs — fuzzy-match draft items against active products, and compose the quotation text + total. The capture controller exposes `buildQuotation(...)` from the current draft and a `save({quoteText})` that appends a `quote_sent` activity. The CaptureScreen adds a "Send quote" action that reads the business profile + catalog, previews the composed message in a bottom sheet, and on confirm launches `wa.me` with the prefilled text and saves the enquiry with the quote recorded. Voice input already exists (the mic button feeds the same pipeline); the Android call-ended nudge is deferred to the later native batch (with Slice C2).

**Tech Stack:** Flutter/Dart, Riverpod, `url_launcher` (WhatsApp share), existing `Money.inr`, `BusinessProfile`/`Product` models, Supabase (`leads.activities` jsonb).

## File Structure

**New:**
- `lib/features/quotations/data/quotation.dart` — `QuoteLine`, `Quotation`, `Quotation.compose(...)`, and `matchCatalog(items, products)`. Pure, no I/O.
- `test/features/quotations/quotation_test.dart` — matcher + compose unit tests.

**Modified:**
- `lib/features/enquiries/data/enquiries_service.dart` — `addEnquiry` gains `quoteText`; appends a `quote_sent` activity when present.
- `lib/features/enquiries/controller/capture_provider.dart` — `buildQuotation(...)` from the draft; `save({quoteText})`.
- `lib/features/enquiries/presentation/capture_screen.dart` — "Send quote" action + preview sheet + WhatsApp share.
- `test/features/enquiries/capture_controller_test.dart` — `buildQuotation` + `save(quoteText:)` forwarding; `FakeEnquiriesService.addEnquiry` gains `quoteText`.
- `test/features/enquiries/capture_screen_test.dart` — "Send quote" visibility + preview sheet.

---

### Task 1: Quotation model — fuzzy match + compose

**Files:**
- Create: `lib/features/quotations/data/quotation.dart`
- Test: `test/features/quotations/quotation_test.dart`

Two pure functions with no dependencies beyond `DraftItem`, `Product`, and `Money`. `matchCatalog` enriches each draft item: if a product's name case-insensitively contains the item name (or vice-versa), adopt the product's name and use its price when the item has none. `Quotation.compose` renders the message and total.

- [ ] **Step 1: Write the failing tests**

Create `test/features/quotations/quotation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';

void main() {
  const products = [
    Product(id: 'p1', name: 'Silk Saree', price: 2500),
    Product(id: 'p2', name: 'Cotton Kurti', price: 800),
  ];

  test('matchCatalog fills price and canonical name from a fuzzy match', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'saree', qty: 2)],
      products,
    );
    expect(lines, hasLength(1));
    expect(lines.single.name, 'Silk Saree'); // canonical catalog name
    expect(lines.single.qty, 2);
    expect(lines.single.unitPrice, 2500); // pulled from catalog
  });

  test('matchCatalog keeps the draft price when the item already has one', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'saree', qty: 1, price: 3000)],
      products,
    );
    expect(lines.single.unitPrice, 3000); // explicit price wins
  });

  test('matchCatalog leaves an unmatched item free-text at price 0', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'dupatta', qty: 1)],
      products,
    );
    expect(lines.single.name, 'dupatta');
    expect(lines.single.unitPrice, 0);
  });

  test('compose renders lines, total and UPI', () {
    final quote = Quotation.compose(
      businessName: 'Rekha Boutique',
      upiId: 'rekha@upi',
      upiName: 'Rekha',
      customerName: 'Priya',
      lines: const [
        QuoteLine(name: 'Silk Saree', qty: 2, unitPrice: 2500),
        QuoteLine(name: 'Blouse', qty: 1, unitPrice: 500),
      ],
    );
    expect(quote.total, 5500);
    expect(quote.message, contains('Rekha Boutique'));
    expect(quote.message, contains('Priya'));
    expect(quote.message, contains('Silk Saree x 2'));
    expect(quote.message, contains('₹5,500'));
    expect(quote.message, contains('rekha@upi'));
  });

  test('compose omits the UPI line when no UPI id is set', () {
    final quote = Quotation.compose(
      businessName: 'Shop',
      upiId: null,
      upiName: null,
      customerName: null,
      lines: const [QuoteLine(name: 'Item', qty: 1, unitPrice: 100)],
    );
    expect(quote.message.toLowerCase(), isNot(contains('upi')));
    expect(quote.total, 100);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/quotations/quotation_test.dart`
Expected: FAIL — target of URI doesn't exist (`quotation.dart`).

- [ ] **Step 3: Implement the model**

Create `lib/features/quotations/data/quotation.dart`:

```dart
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
  const Quotation({required this.lines, required this.total, required this.message});

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
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/quotations/quotation_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/quotations/data/quotation.dart test/features/quotations/quotation_test.dart
git commit -m "feat(quotations): catalog fuzzy-match and quotation composer"
```

---

### Task 2: Record the sent quote as an activity

**Files:**
- Modify: `lib/features/enquiries/data/enquiries_service.dart`
- Modify: `lib/features/enquiries/controller/capture_provider.dart`
- Test: `test/features/enquiries/capture_controller_test.dart`

`addEnquiry` gains an optional `quoteText`; when present it seeds a second `quote_sent` activity next to `created`. The controller's `save` forwards it. (Quotes attach on the enquiry save path; the order path is unchanged.)

- [ ] **Step 1: Write the failing test**

In `test/features/enquiries/capture_controller_test.dart`, first update `FakeEnquiriesService.addEnquiry` to accept and record `quoteText` (add the param and store it), then add a test. Update the override:

```dart
  @override
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
    String? screenshotPath,
    String? quoteText,
  }) async {
    enquiries.add({
      'customer_id': customerId,
      'product_id': productId,
      'source': source,
      'status': followUpDate != null ? 'follow' : 'new',
      'screenshot_path': screenshotPath,
      'quote_text': quoteText,
    });
    return Enquiry.fromMap({'id': 'e-new', 'customer_id': customerId});
  }
```

Add this test inside `main()`:

```dart
test('save forwards the quote text to addEnquiry', () async {
  final customers = FakeCustomersService();
  final enquiries = FakeEnquiriesService();
  final c = makeContainer(customers, enquiries);
  final controller = c.read(captureControllerProvider.notifier);

  controller.setText('Priya wants a saree');
  await controller.save(quoteText: 'QUOTE-BODY');

  expect(enquiries.enquiries.single['quote_text'], 'QUOTE-BODY');
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: FAIL — `save` has no `quoteText` parameter.

- [ ] **Step 3: Add `quoteText` to `addEnquiry`**

In `lib/features/enquiries/data/enquiries_service.dart`, add the parameter and the conditional activity. Update the signature and the `activities` array. The new signature line adds `String? quoteText,` after `screenshotPath`. Replace the `activities` list literal with:

```dart
          'activities': [
            {
              'type': 'created',
              'note': 'Enquiry captured',
              'time': DateTime.now().toIso8601String(),
            },
            if (quoteText != null && quoteText.isNotEmpty)
              {
                'type': 'quote_sent',
                'note': quoteText,
                'time': DateTime.now().toIso8601String(),
              },
          ],
```

The full updated signature:

```dart
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
    String? screenshotPath,
    String? quoteText,
  }) async {
```

- [ ] **Step 4: Forward `quoteText` from the controller**

In `lib/features/enquiries/controller/capture_provider.dart`, change `save`'s signature and the `addEnquiry` call. Update the signature:

```dart
  Future<SaveResult> save({String? quoteText}) async {
```

And add `quoteText: quoteText,` to the `addEnquiry` call (the enquiry branch), so it becomes:

```dart
      await _enquiries.addEnquiry(
        customerId: customer.id!,
        productId: state.attachedProductId,
        source: state.screenshotPath != null ? 'screenshot' : source,
        message: draft.raw.trim(),
        intent: draft.intent,
        followUpDate: draft.followUpDate,
        screenshotPath: state.screenshotPath,
        quoteText: quoteText,
      );
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: PASS (existing + the new forwarding test).

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/data/enquiries_service.dart lib/features/enquiries/controller/capture_provider.dart test/features/enquiries/capture_controller_test.dart
git commit -m "feat(enquiries): record a sent quote as an enquiry activity"
```

---

### Task 3: buildQuotation from the draft

**Files:**
- Modify: `lib/features/enquiries/controller/capture_provider.dart`
- Test: `test/features/enquiries/capture_controller_test.dart`

A controller method that turns the current draft into a `Quotation`, given the business identity and the catalog. It matches the draft items and composes with the draft's customer name.

- [ ] **Step 1: Write the failing test**

In `test/features/enquiries/capture_controller_test.dart`, add the imports at the top (if missing):

```dart
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';
```

Add this test inside `main()`:

```dart
test('buildQuotation composes from the draft, catalog and business', () async {
  final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
  final controller = c.read(captureControllerProvider.notifier);

  controller.setText('Priya wants 2 saree');

  final quote = controller.buildQuotation(
    businessName: 'Rekha Boutique',
    upiId: 'rekha@upi',
    upiName: 'Rekha',
    products: const [Product(id: 'p1', name: 'Silk Saree', price: 2500)],
  );

  expect(quote.total, 5000);
  expect(quote.message, contains('Rekha Boutique'));
  expect(quote.message, contains('Silk Saree x 2'));
  expect(quote.message, contains('₹5,000'));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: FAIL — `buildQuotation` is not defined.

- [ ] **Step 3: Implement `buildQuotation`**

In `lib/features/enquiries/controller/capture_provider.dart`, add the imports at the top:

```dart
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';
```

Add the method to `CaptureController` (place it after `save`):

```dart
  Quotation buildQuotation({
    required String businessName,
    required String? upiId,
    required String? upiName,
    required List<Product> products,
  }) {
    final lines = matchCatalog(state.draft.items, products);
    return Quotation.compose(
      businessName: businessName,
      upiId: upiId,
      upiName: upiName,
      customerName: state.draft.name,
      lines: lines,
    );
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/controller/capture_provider.dart test/features/enquiries/capture_controller_test.dart
git commit -m "feat(enquiries): buildQuotation from the capture draft"
```

---

### Task 4: Send-quote action + preview sheet

**Files:**
- Modify: `lib/features/enquiries/presentation/capture_screen.dart`
- Test: `test/features/enquiries/capture_screen_test.dart`

A "Send quote" button appears when the draft has items. Tapping it reads the business profile + catalog, composes the quotation, and shows a preview bottom sheet with the message and a "Share on WhatsApp" button. Sharing launches `wa.me` with the prefilled text, saves the enquiry recording the quote, and closes the capture screen.

- [ ] **Step 1: Write the failing test**

The existing `test/features/enquiries/capture_screen_test.dart` uses `wrap(child, enquiries)` which overrides the enquiry/customer/AI providers. The Send-quote button also reads `businessProfileProvider` and `productsControllerProvider`; the default (real) providers would hit Supabase, so the test overrides them. Add these imports at the top of the test file:

```dart
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/data/products_service.dart';
```

Add a fake products service (mirrors the catalog test's fake, minimal) near the top of the file, plus a helper that wraps with business + catalog overrides:

```dart
class _StubProductsService implements ProductsService {
  @override
  Future<List<Product>> fetchProducts() async =>
      const [Product(id: 'p1', name: 'Silk Saree', price: 2500)];
  @override
  Future<Product> addProduct(Product product) async => product;
  @override
  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async =>
      const Product(id: 'p1', name: 'Silk Saree', price: 2500);
  @override
  Future<void> archiveProduct(String id) async {}
  @override
  Future<String> uploadImage(String localPath) async => 'x';
  @override
  Future<void> removeImages(List<String> paths) async {}
  @override
  Future<String> signedUrl(String path) async => 'https://s/$path';
}

Widget wrapQuote(Widget child, FakeEnquiriesService enquiries) {
  return ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(FakeCustomersService()),
      enquiriesServiceProvider.overrideWithValue(enquiries),
      aiParseServiceProvider.overrideWithValue(FakeAiParseService(null)),
      productsServiceProvider.overrideWithValue(_StubProductsService()),
      businessProfileProvider.overrideWith(
          (ref) async => const BusinessProfile(name: 'Rekha Boutique')),
    ],
    child: MaterialApp(home: child),
  );
}
```

Add the imports the wrap needs (`aiParseServiceProvider`, `FakeAiParseService`, `FakeCustomersService` are already imported via the existing `show`; ensure `aiParseServiceProvider` is imported from `capture_provider.dart` — the existing test file already imports it). Add the test:

```dart
testWidgets('Send quote previews the composed message', (tester) async {
  await tester.pumpWidget(wrapQuote(const CaptureScreen(), FakeEnquiriesService()));

  await tester.enterText(
      find.byKey(const Key('capture-input')), 'Priya wants 2 saree');
  await tester.pump(const Duration(milliseconds: 400));

  expect(find.text('Send quote'), findsOneWidget);
  await tester.tap(find.text('Send quote'));
  await tester.pumpAndSettle();

  expect(find.textContaining('Rekha Boutique'), findsOneWidget);
  expect(find.textContaining('Silk Saree x 2'), findsOneWidget);
  expect(find.text('Share on WhatsApp'), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_screen_test.dart`
Expected: FAIL — no "Send quote" button.

- [ ] **Step 3: Add the action + preview sheet**

In `lib/features/enquiries/presentation/capture_screen.dart`, add imports:

```dart
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';
```

Add a method to `_CaptureScreenState`:

```dart
  Future<void> _sendQuote() async {
    final profile = ref.read(businessProfileProvider).valueOrNull;
    final products =
        ref.read(productsControllerProvider).valueOrNull ?? const [];
    final controller = ref.read(captureControllerProvider.notifier);
    final draft = ref.read(captureControllerProvider).draft;

    final quote = controller.buildQuotation(
      businessName: profile?.name ?? 'My Shop',
      upiId: profile?.upiId,
      upiName: profile?.upiName,
      products: products,
    );

    final messenger = ScaffoldMessenger.of(context);
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Quotation preview',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            SelectableText(quote.message),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(
              label: 'Share on WhatsApp',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );

    if (send != true || !mounted) return;

    final phone = draft.phone;
    final waBase = (phone != null && phone.isNotEmpty)
        ? 'https://wa.me/91$phone'
        : 'https://wa.me/';
    final uri = Uri.parse('$waBase?text=${Uri.encodeComponent(quote.message)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    try {
      await controller.save(quoteText: quote.message);
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ref.read(enquiriesControllerProvider.notifier).load();
      NotificationService.syncLeadNotifications().catchError((_) {});
      messenger.showSnackBar(
        const SnackBar(content: Text('Quote shared and enquiry saved')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Shared, but could not save. Try again.')),
      );
    }
  }
```

Add the "Send quote" button below the save button, inside the `if (hasContent) ...[` block, shown only when the draft has items. After the `AppPrimaryButton(... _save ...)` widget, add:

```dart
            if (draft.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _sendQuote,
                icon: const Icon(Icons.request_quote_outlined, size: 18),
                label: const Text('Send quote'),
              ),
            ],
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/enquiries/capture_screen_test.dart`
Expected: PASS (existing + the preview test). Note: the test taps "Share on WhatsApp" is NOT exercised (the `launchUrl` platform channel is unavailable in widget tests); the test only asserts the preview renders. Do not add a tap-to-share assertion.

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/presentation/capture_screen.dart test/features/enquiries/capture_screen_test.dart
git commit -m "feat(enquiries): send-quote action with WhatsApp share and preview"
```

---

### Task 5: Final gate + review

**Files:** none (verification + review).

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all pass (89 from Slice C1 + the additions here).

- [ ] **Step 3: Final code review**

Dispatch the code-reviewer agent over the whole slice (`git diff <Task-1-commit>^..HEAD`). Focus: the quote message contains no injected/unsanitized data that could break the `wa.me` URL (it is URL-encoded); the quote is only sent on explicit tap (manual approval); the recorded activity is bounded text; catalog match is case-insensitive and safe on empty names; no secrets. Fix verified findings with implementer subagents and re-review.

- [ ] **Step 4: Finish the branch**

Use superpowers:finishing-a-development-branch. Then deliver a summary + device smoke checklist: capture (paste or speak) a message with items → "Send quote" → preview shows business name, catalog-priced lines, total, UPI → "Share on WhatsApp" opens WhatsApp with the prefilled message to the customer's number → enquiry saved with a `quote_sent` activity.

---

## Self-Review

**1. Spec coverage (Slice D quotation half):**
- "parsed item names fuzzy-matched (case-insensitive contains) against active products → attach product, pull price; unmatched items stay free-text with parsed price" → Task 1 `matchCatalog`.
- "plain-text message — business name, line items (name × qty @ price), total, UPI ID when set — previewed on screen" → Task 1 `Quotation.compose`, Task 4 preview sheet.
- "sent only on explicit tap via WhatsApp share" → Task 4 (`_sendQuote` shows the sheet; `launchUrl` only fires after the explicit "Share on WhatsApp" tap; manual approval satisfied).
- "Stored as an activity entry on the enquiry (`activities` jsonb)" → Task 2 `quote_sent` activity via `addEnquiry(quoteText:)`.
- Voice input "continuous speech-to-text fills the paste box" already exists (mic button → same pipeline); the Android call-ended nudge and PDF quotes are explicitly out of this trimmed slice — noted in the header.

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to". Every code step is complete. The one non-obvious constraint (widget test cannot exercise `launchUrl`) is stated with the exact instruction not to assert on it.

**3. Type consistency:** `QuoteLine{name, qty, unitPrice}` and `Quotation{lines, total, message}` are defined in Task 1 and used identically in Tasks 3–4. `matchCatalog(List<DraftItem>, List<Product>)` and `Quotation.compose({businessName, upiId, upiName, customerName, lines})` signatures match their call in `buildQuotation` (Task 3). `save({String? quoteText})` (Task 2) matches the `_sendQuote` call (Task 4). `addEnquiry`'s new `quoteText` (Task 2) matches both fakes and the controller call. `businessProfileProvider` (FutureProvider) and `productsControllerProvider` (AsyncValue) are read via `.valueOrNull`, consistent with their definitions.
