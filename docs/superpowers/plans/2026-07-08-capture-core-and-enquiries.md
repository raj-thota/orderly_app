# Capture Core + Enquiries Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One paste-first CaptureScreen that turns a WhatsApp chat (or manual/voice input) into a linked customer + enquiry (or order), plus a rebuilt Enquiries tab on typed models — Slice A of `docs/superpowers/specs/2026-07-07-capture-flow-and-enquiries-design.md`.

**Architecture:** New `lib/features/enquiries/` feature follows the catalog pattern exactly (typed models with `fromMap`/`toMap`, thin Supabase service, auth-scoped Riverpod `StateNotifierProvider`). Order creation is atomic via a Postgres RPC (`create_order_with_items`, security invoker so RLS applies). Legacy screens that survive this slice (Dashboard, Orders, notifications) keep working through a compatibility shim: `LeadsController` keeps its provider/API but is re-backed by the new data layer emitting legacy-shaped maps. Legacy capture screens are deleted.

**Tech Stack:** Flutter, Riverpod (StateNotifier), Supabase (Postgres RPC, RLS), speech_to_text (already integrated), url_launcher (wa.me / tel links).

**Context you need before starting:**
- Repo: `/Users/rajuthota/Desktop/work/closr/orderly_app`, branch `spec/social-seller-pipeline`.
- Schema truth: `supabase/migrations/0001_core_schema.sql`. Key columns: `leads(message, intent, status new|follow|won|lost, follow_up_date, customer_id, product_id, source dm|paste|product|manual, activities jsonb)`, `customers(name, phone, unique(user_id,phone))`, `orders`, `order_items(order_id not null, name, unit_price, qty, line_total)`.
- The legacy data layer (`lib/core/services/leads_service.dart`) targets *old* columns (`msg`, `order_items.lead_id`) and is already broken against this schema. Legacy read paths get re-backed; legacy write paths get replaced or deleted.
- Design tokens: `AppColors`, `AppSpacing`, `AppRadius` (`lib/core/theme/`), `Money.inr` (`lib/core/utils/money.dart`), `StatusPill`, `AppCard`, `AppPrimaryButton` (`lib/shared/widgets/`).
- Pattern reference for providers/tests: `lib/features/catalog/controller/products_provider.dart` and `test/features/catalog/products_controller_test.dart`.
- Verification commands: `flutter analyze` (baseline: 7 pre-existing infos in `lead_card.dart` / `add_entry_screen.dart` — both die in this plan, so final baseline is 0), `flutter test`.
- DB changes are applied to Supabase project `dgviploqkwyuttcdnddq` via the Supabase MCP `apply_migration` tool; run `get_advisors` after.

---

### Task 1: Migration 0005 — nullable customer phone + atomic order RPC

`customers.phone` is `not null` + `unique(user_id, phone)`, which forbids the spec's phone-less customers (two of them would collide). The RPC makes order+items+booking+lead-status one atomic statement (spec §5: "no partial writes").

**Files:**
- Create: `supabase/migrations/0005_capture_support.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- Capture slice support: phone-less customers + atomic order creation.

-- customers.phone becomes optional; uniqueness applies only when present.
alter table public.customers alter column phone drop not null;
alter table public.customers drop constraint customers_user_id_phone_key;
create unique index customers_user_phone_unique
  on public.customers(user_id, phone) where phone is not null;

-- Atomic order creation used by capture save-as-order and enquiry conversion.
-- security invoker: every statement runs under the caller's RLS policies.
create or replace function public.create_order_with_items(
  p_customer_id uuid,
  p_lead_id uuid,
  p_items jsonb,
  p_book_product_id uuid default null,
  p_notes text default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_price numeric(12,2);
  v_qty integer;
begin
  insert into orders (user_id, customer_id, lead_id, notes)
  values (auth.uid(), p_customer_id, p_lead_id, p_notes)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_qty := greatest(coalesce((v_item->>'qty')::integer, 1), 1);

    insert into order_items
      (user_id, order_id, product_id, name, image_url, unit_price, gst_rate, qty, line_total)
    values (
      auth.uid(),
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(nullif(v_item->>'name', ''), 'Item'),
      v_item->>'image_url',
      v_price,
      coalesce((v_item->>'gst_rate')::numeric, 0),
      v_qty,
      v_price * v_qty
    );

    v_subtotal := v_subtotal + v_price * v_qty;
  end loop;

  update orders set subtotal = v_subtotal, grand_total = v_subtotal
  where id = v_order_id;

  if p_lead_id is not null then
    update leads set status = 'won'
    where id = p_lead_id and user_id = auth.uid();
  end if;

  if p_book_product_id is not null then
    update products set piece_status = 'booked'
    where id = p_book_product_id and user_id = auth.uid() and is_unique;
  end if;

  return v_order_id;
end;
$$;

revoke all on function public.create_order_with_items(uuid, uuid, jsonb, uuid, text) from public, anon;
grant execute on function public.create_order_with_items(uuid, uuid, jsonb, uuid, text) to authenticated;
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `mcp__claude_ai_Supabase__apply_migration` with `project_id: dgviploqkwyuttcdnddq`, `name: capture_support`, and the SQL above. Before applying, sanity-check with `execute_sql` (read-only): `select count(*) from customers;` (expect it to succeed).

- [ ] **Step 3: Verify + advisors**

`execute_sql`: `select proname, prosecdef from pg_proc where proname = 'create_order_with_items';` → one row, `prosecdef = false` (invoker).
Run `mcp__claude_ai_Supabase__get_advisors` (type security) → no NEW findings beyond the 8 known baseline WARNs.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0005_capture_support.sql
git commit -m "feat(db): nullable customer phone + atomic create_order_with_items RPC"
```

---

### Task 2: Customer + Enquiry models

**Files:**
- Create: `lib/features/enquiries/data/customer.dart`
- Create: `lib/features/enquiries/data/enquiry.dart`
- Test: `test/features/enquiries/customer_test.dart`
- Test: `test/features/enquiries/enquiry_test.dart`

- [ ] **Step 1: Write failing tests**

`test/features/enquiries/customer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/customer.dart';

void main() {
  test('fromMap parses a row', () {
    final c = Customer.fromMap({
      'id': 'c1',
      'name': 'Priya',
      'phone': '9876543210',
      'tags': ['vip'],
    });
    expect(c.id, 'c1');
    expect(c.name, 'Priya');
    expect(c.phone, '9876543210');
    expect(c.tags, ['vip']);
  });

  test('fromMap tolerates null phone and missing tags', () {
    final c = Customer.fromMap({'id': 'c2', 'name': 'Walk-in'});
    expect(c.phone, isNull);
    expect(c.tags, isEmpty);
  });

  test('toMap omits nulls and never includes id/user_id', () {
    const c = Customer(name: 'Priya', phone: '9876543210');
    final map = c.toMap();
    expect(map, {'name': 'Priya', 'phone': '9876543210'});
  });
}
```

`test/features/enquiries/enquiry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';

void main() {
  final row = {
    'id': 'e1',
    'customer_id': 'c1',
    'product_id': 'p1',
    'source': 'paste',
    'message': 'Want the red saree',
    'intent': 'inquiry',
    'status': 'follow',
    'follow_up_date': '2026-07-10T00:00:00.000Z',
    'created_at': '2026-07-08T10:00:00.000Z',
    'customers': {'name': 'Priya', 'phone': '9876543210'},
    'products': {
      'name': 'Red Banarasi',
      'images': ['u1/a.jpg'],
      'price': 5500,
      'is_unique': true,
      'piece_status': 'available',
    },
  };

  test('fromMap flattens customer and product joins', () {
    final e = Enquiry.fromMap(row);
    expect(e.id, 'e1');
    expect(e.customerName, 'Priya');
    expect(e.customerPhone, '9876543210');
    expect(e.productName, 'Red Banarasi');
    expect(e.productImage, 'u1/a.jpg');
    expect(e.productPrice, 5500);
    expect(e.productIsUnique, isTrue);
    expect(e.followUpDate, DateTime.utc(2026, 7, 10));
  });

  test('fromMap tolerates missing joins', () {
    final e = Enquiry.fromMap({'id': 'e2', 'status': 'new'});
    expect(e.customerName, isNull);
    expect(e.productName, isNull);
    expect(e.status, 'new');
  });

  test('bucket assigns overdue/today/upcoming/new', () {
    final now = DateTime(2026, 7, 8, 12);
    Enquiry withFollow(DateTime? d, String status) => Enquiry.fromMap({
          'id': 'x',
          'status': status,
          'follow_up_date': d?.toIso8601String(),
        });
    expect(withFollow(DateTime(2026, 7, 7), 'follow').bucket(now),
        EnquiryBucket.overdue);
    expect(withFollow(DateTime(2026, 7, 8, 18), 'follow').bucket(now),
        EnquiryBucket.today);
    expect(withFollow(DateTime(2026, 7, 9), 'follow').bucket(now),
        EnquiryBucket.upcoming);
    expect(withFollow(null, 'new').bucket(now), EnquiryBucket.fresh);
  });
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -5`
Expected: FAIL — files don't exist / classes undefined.

- [ ] **Step 3: Implement the models**

`lib/features/enquiries/data/customer.dart`:

```dart
class Customer {
  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.tags = const [],
    this.createdAt,
  });

  final String? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final List<String> tags;
  final DateTime? createdAt;

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      address: map['address']?.toString(),
      notes: map['notes']?.toString(),
      tags: [for (final t in (map['tags'] as List? ?? const [])) t.toString()],
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
        if (notes != null) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
      };
}
```

`lib/features/enquiries/data/enquiry.dart`:

```dart
enum EnquiryBucket { overdue, today, upcoming, fresh }

class Enquiry {
  const Enquiry({
    this.id,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.productId,
    this.productName,
    this.productImage,
    this.productIsUnique = false,
    this.productPrice,
    this.source = 'manual',
    this.message,
    this.intent,
    this.status = 'new',
    this.followUpDate,
    this.followUpNote,
    this.activities = const [],
    this.createdAt,
  });

  final String? id;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? productId;
  final String? productName;
  final String? productImage;
  final bool productIsUnique;
  final double? productPrice;
  final String source;
  final String? message;
  final String? intent;
  final String status;
  final DateTime? followUpDate;
  final String? followUpNote;
  final List<Map<String, dynamic>> activities;
  final DateTime? createdAt;

  factory Enquiry.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    final product = map['products'];
    final images =
        product is Map ? (product['images'] as List? ?? const []) : const [];
    return Enquiry(
      id: map['id']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
      productId: map['product_id']?.toString(),
      productName: product is Map ? product['name']?.toString() : null,
      productImage: images.isEmpty ? null : images.first.toString(),
      productIsUnique: product is Map && product['is_unique'] == true,
      productPrice: product is Map
          ? double.tryParse(product['price']?.toString() ?? '')
          : null,
      source: (map['source'] ?? 'manual').toString(),
      message: map['message']?.toString(),
      intent: map['intent']?.toString(),
      status: (map['status'] ?? 'new').toString(),
      followUpDate:
          DateTime.tryParse(map['follow_up_date']?.toString() ?? ''),
      followUpNote: map['follow_up_note']?.toString(),
      activities: [
        for (final a in (map['activities'] as List? ?? const []))
          if (a is Map) Map<String, dynamic>.from(a),
      ],
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  EnquiryBucket bucket(DateTime now) {
    final due = followUpDate;
    if (status == 'follow' && due != null) {
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startOfTomorrow = startOfToday.add(const Duration(days: 1));
      if (due.isBefore(startOfToday)) return EnquiryBucket.overdue;
      if (due.isBefore(startOfTomorrow)) return EnquiryBucket.today;
      return EnquiryBucket.upcoming;
    }
    return EnquiryBucket.fresh;
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/data/customer.dart lib/features/enquiries/data/enquiry.dart test/features/enquiries/customer_test.dart test/features/enquiries/enquiry_test.dart
git commit -m "feat(enquiries): typed Customer and Enquiry models with buckets"
```

---

### Task 3: CaptureDraft + upgraded rules parser

Replaces the naive `MessageParser` output with a typed draft. Old `MessageParser` stays until Task 11 deletes its last consumer.

**Files:**
- Create: `lib/features/enquiries/data/capture_draft.dart`
- Test: `test/features/enquiries/capture_draft_test.dart`

- [ ] **Step 1: Write failing tests**

`test/features/enquiries/capture_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';

void main() {
  test('extracts 10-digit phone with optional +91', () {
    expect(CaptureDraft.fromText('call me on +91 98765 43210').phone,
        '9876543210');
    expect(CaptureDraft.fromText('number 9876543210').phone, '9876543210');
    expect(CaptureDraft.fromText('order 12345').phone, isNull);
  });

  test('extracts name from self-introduction patterns', () {
    expect(CaptureDraft.fromText('Hi this is Priya, want 2 sarees').name,
        'Priya');
    expect(CaptureDraft.fromText("I'm Anita from Pune").name, 'Anita');
    expect(CaptureDraft.fromText('Priya: want the red one').name, 'Priya');
  });

  test('extracts qty + item pairs and rupee prices', () {
    final d = CaptureDraft.fromText('want 2 kurtis at ₹1,500 and 1 saree');
    expect(d.items, hasLength(2));
    expect(d.items.first.name, 'kurtis');
    expect(d.items.first.qty, 2);
    expect(d.items.first.price, 1500);
    expect(d.items.last.name, 'saree');
    expect(d.items.last.qty, 1);
  });

  test('detects order type and follow-up intent with dates', () {
    expect(CaptureDraft.fromText('please confirm my order').type, 'order');
    final d = CaptureDraft.fromText('will confirm tomorrow');
    expect(d.type, 'enquiry');
    expect(d.intent, 'follow_up');
    expect(d.followUpDate, isNotNull);
  });

  test('empty text yields empty draft', () {
    final d = CaptureDraft.fromText('   ');
    expect(d.isEmpty, isTrue);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/enquiries/capture_draft_test.dart 2>&1 | tail -5`
Expected: FAIL — `capture_draft.dart` doesn't exist.

- [ ] **Step 3: Implement**

`lib/features/enquiries/data/capture_draft.dart`:

```dart
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

  static final _phoneRe = RegExp(r'(?:\+91[\s-]?)?([6-9]\d{4}[\s-]?\d{5})');
  static final _nameRe = RegExp(
      r"(?:this is|i am|i'm|from)\s+([A-Z][a-z]+)|^([A-Z][a-z]+):",
      caseSensitive: false);
  static final _itemRe = RegExp(r'\b(\d{1,3})\s+([a-z]+)');
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

    final isOrder = lower.contains('confirm') ||
        lower.contains('order') ||
        lower.contains('book');
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

    return CaptureDraft(
      name: name,
      phone: phone,
      items: items,
      intent: isOrder ? 'order' : (wantsFollowUp ? 'follow_up' : 'inquiry'),
      type: isOrder ? 'order' : 'enquiry',
      followUpDate: followUp,
      raw: text,
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/features/enquiries/capture_draft_test.dart 2>&1 | tail -3`
Expected: `All tests passed!` (Adjust regexes only if a listed test fails; do not weaken tests.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/data/capture_draft.dart test/features/enquiries/capture_draft_test.dart
git commit -m "feat(enquiries): CaptureDraft rules parser (phone, name, items, intent, dates)"
```

---

### Task 4: Customers + Enquiries services

Thin Supabase clients (catalog pattern). Tested through fakes at controller level (Task 6); the pure legacy-map shaping gets a direct unit test here.

**Files:**
- Create: `lib/features/enquiries/data/customers_service.dart`
- Create: `lib/features/enquiries/data/enquiries_service.dart`
- Test: `test/features/enquiries/legacy_map_test.dart`

- [ ] **Step 1: Implement CustomersService**

`lib/features/enquiries/data/customers_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer.dart';

class CustomersService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// Links to the existing customer with this phone, else creates one.
  /// Phone-less customers are always created fresh (mergeable later).
  Future<Customer> createOrLink({required String name, String? phone}) async {
    final cleanPhone = (phone ?? '').trim().isEmpty ? null : phone!.trim();

    if (cleanPhone != null) {
      final existing = await _client
          .from('customers')
          .select()
          .eq('user_id', _userId)
          .eq('phone', cleanPhone)
          .maybeSingle();
      if (existing != null) return Customer.fromMap(existing);
    }

    final row = await _client
        .from('customers')
        .insert({
          'user_id': _userId,
          'name': name.trim().isEmpty ? 'Customer' : name.trim(),
          if (cleanPhone != null) 'phone': cleanPhone,
        })
        .select()
        .single();
    return Customer.fromMap(row);
  }
}
```

- [ ] **Step 2: Implement EnquiriesService**

`lib/features/enquiries/data/enquiries_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'capture_draft.dart';
import 'enquiry.dart';

const _selectWithJoins =
    '*, customers(name, phone), products(name, images, price, is_unique, piece_status)';

class EnquiriesService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<Enquiry>> fetchEnquiries() async {
    final rows = await _client
        .from('leads')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .inFilter('status', ['new', 'follow'])
        .order('created_at', ascending: false);
    return rows.map<Enquiry>((r) => Enquiry.fromMap(r)).toList();
  }

  Future<Enquiry?> fetchById(String id) async {
    final row = await _client
        .from('leads')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Enquiry.fromMap(row);
  }

  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
  }) async {
    final row = await _client
        .from('leads')
        .insert({
          'user_id': _userId,
          'customer_id': customerId,
          if (productId != null) 'product_id': productId,
          'source': source,
          if (message != null && message.isNotEmpty) 'message': message,
          if (intent != null) 'intent': intent,
          'status': followUpDate != null ? 'follow' : 'new',
          if (followUpDate != null)
            'follow_up_date': followUpDate.toIso8601String(),
          'activities': [
            {
              'type': 'created',
              'note': 'Enquiry captured',
              'time': DateTime.now().toIso8601String(),
            }
          ],
        })
        .select(_selectWithJoins)
        .single();
    return Enquiry.fromMap(row);
  }

  Future<void> updateEnquiry(String id, Map<String, dynamic> changes) async {
    await _client
        .from('leads')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// Atomic: order + items + lead → won + optional unique-piece booking.
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    final payload = <Map<String, dynamic>>[
      for (var i = 0; i < items.length; i++)
        {
          'name': items[i].name,
          'qty': items[i].qty,
          'unit_price': items[i].price ?? 0,
          if (productIds != null && productIds[i] != null)
            'product_id': productIds[i],
        }
    ];
    final orderId = await _client.rpc('create_order_with_items', params: {
      'p_customer_id': customerId,
      'p_lead_id': leadId,
      'p_items': payload,
      'p_book_product_id': bookProductId,
      'p_notes': notes,
    });
    return orderId.toString();
  }

  /// Legacy-shaped maps for surviving pre-spec screens (Dashboard, Orders,
  /// notifications). Retired when stages 4 and 7 rebuild those screens.
  Future<List<Map<String, dynamic>>> fetchLegacyMaps() async {
    final leads = await _client
        .from('leads')
        .select('*, customers(name, phone)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    final orders = await _client
        .from('orders')
        .select('*, customers(name, phone), order_items(*)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return buildLegacyMaps(
      leads: List<Map<String, dynamic>>.from(leads),
      orders: List<Map<String, dynamic>>.from(orders),
    );
  }
}

/// Pure mapping so it can be unit-tested without Supabase.
/// Legacy screens expect: name, msg, status ("closed" = order), items with
/// product_name/quantity/price/total, follow_up_date, intent.
List<Map<String, dynamic>> buildLegacyMaps({
  required List<Map<String, dynamic>> leads,
  required List<Map<String, dynamic>> orders,
}) {
  String customerName(Map<String, dynamic> row) {
    final c = row['customers'];
    return c is Map ? (c['name'] ?? 'Customer').toString() : 'Customer';
  }

  final result = <Map<String, dynamic>>[];

  for (final lead in leads) {
    if (lead['status'] == 'won') continue; // shown via its order row
    result.add({
      ...lead,
      'name': customerName(lead),
      'msg': lead['message'] ?? '',
      'items': const <Map<String, dynamic>>[],
    });
  }

  for (final order in orders) {
    result.add({
      'id': order['id'],
      'order_id': order['id'],
      'name': customerName(order),
      'msg': order['notes'] ?? '',
      'status': 'closed',
      'order_status': order['status'] ?? 'pending',
      'intent': 'order',
      'created_at': order['created_at'],
      'follow_up_date': null,
      'activities': const <Map<String, dynamic>>[],
      'items': [
        for (final item in (order['order_items'] as List? ?? const []))
          {
            'product_name': item['name'],
            'quantity': item['qty'],
            'price': item['unit_price'],
            'total': item['line_total'],
          }
      ],
    });
  }

  result.sort((a, b) => (b['created_at'] ?? '')
      .toString()
      .compareTo((a['created_at'] ?? '').toString()));
  return result;
}
```

- [ ] **Step 3: Write + run the legacy-map unit test**

`test/features/enquiries/legacy_map_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';

void main() {
  test('leads keep legacy keys; won leads are skipped', () {
    final maps = buildLegacyMaps(
      leads: [
        {
          'id': 'l1',
          'status': 'follow',
          'message': 'wants saree',
          'created_at': '2026-07-08T10:00:00Z',
          'customers': {'name': 'Priya'},
        },
        {'id': 'l2', 'status': 'won', 'created_at': '2026-07-08T09:00:00Z'},
      ],
      orders: [],
    );
    expect(maps, hasLength(1));
    expect(maps.first['name'], 'Priya');
    expect(maps.first['msg'], 'wants saree');
  });

  test('orders become status closed with legacy item keys', () {
    final maps = buildLegacyMaps(leads: [], orders: [
      {
        'id': 'o1',
        'status': 'pending',
        'created_at': '2026-07-08T10:00:00Z',
        'customers': {'name': 'Anita'},
        'order_items': [
          {'name': 'Kurti', 'qty': 2, 'unit_price': 500, 'line_total': 1000},
        ],
      }
    ]);
    expect(maps.single['status'], 'closed');
    expect(maps.single['order_status'], 'pending');
    expect(maps.single['items'], [
      {'product_name': 'Kurti', 'quantity': 2, 'price': 500, 'total': 1000},
    ]);
  });
}
```

Run: `flutter test test/features/enquiries/legacy_map_test.dart 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/enquiries/data/customers_service.dart lib/features/enquiries/data/enquiries_service.dart test/features/enquiries/legacy_map_test.dart
git commit -m "feat(enquiries): customers + enquiries services with atomic order RPC and legacy adapter"
```

---

### Task 5: Shared auth provider + enquiries/capture providers

`authUserIdProvider` currently lives in the catalog feature; both features need it → move to core.

**Files:**
- Create: `lib/core/providers/auth_providers.dart`
- Modify: `lib/features/catalog/controller/products_provider.dart` (remove local `authUserIdProvider`, import the core one)
- Create: `lib/features/enquiries/controller/enquiries_provider.dart`
- Create: `lib/features/enquiries/controller/capture_provider.dart`

- [ ] **Step 1: Extract authUserIdProvider to core**

`lib/core/providers/auth_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits the signed-in user id (null when signed out). Feature providers
/// watch this so per-user state resets on login/logout.
final authUserIdProvider = StreamProvider<String?>((ref) {
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
});
```

In `lib/features/catalog/controller/products_provider.dart`: delete the local `authUserIdProvider` definition, add `import 'package:orderly_app/core/providers/auth_providers.dart';`, and re-export it so existing test overrides keep working: add `export 'package:orderly_app/core/providers/auth_providers.dart' show authUserIdProvider;`.

Run: `flutter test test/features/catalog/ 2>&1 | tail -3`
Expected: `All tests passed!` (catalog unaffected).

- [ ] **Step 2: Implement enquiries providers**

`lib/features/enquiries/controller/enquiries_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:orderly_app/core/providers/auth_providers.dart';
import '../data/capture_draft.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import '../data/enquiry.dart';

final customersServiceProvider = Provider<CustomersService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return CustomersService();
});

final enquiriesServiceProvider = Provider<EnquiriesService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return EnquiriesService();
});

final enquiriesControllerProvider = StateNotifierProvider<EnquiriesController,
    AsyncValue<List<Enquiry>>>((ref) {
  return EnquiriesController(ref.watch(enquiriesServiceProvider))..load();
});

class EnquiriesController extends StateNotifier<AsyncValue<List<Enquiry>>> {
  EnquiriesController(this._service) : super(const AsyncValue.loading());

  final EnquiriesService _service;

  Future<void> load() async {
    state = await AsyncValue.guard(_service.fetchEnquiries);
  }

  Future<void> reschedule(String id, DateTime date, {String? note}) async {
    await _service.updateEnquiry(id, {
      'status': 'follow',
      'follow_up_date': date.toIso8601String(),
      if (note != null) 'follow_up_note': note,
    });
    await load();
  }

  Future<void> markLost(String id) async {
    await _service.updateEnquiry(id, {'status': 'lost'});
    await load();
  }

  /// Converts to an order; books the attached unique piece.
  Future<String> convertToOrder(Enquiry enquiry, List<DraftItem> items) async {
    final orderId = await _service.createOrder(
      customerId: enquiry.customerId!,
      leadId: enquiry.id,
      items: items,
      bookProductId: enquiry.productIsUnique ? enquiry.productId : null,
      productIds: [
        for (var i = 0; i < items.length; i++)
          i == 0 ? enquiry.productId : null,
      ],
    );
    await load();
    return orderId;
  }
}
```

`lib/features/enquiries/controller/capture_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/capture_draft.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import 'enquiries_provider.dart';

class CaptureState {
  const CaptureState({
    this.draft = const CaptureDraft(),
    this.attachedProductId,
    this.attachedProductName,
    this.attachedProductIsUnique = false,
    this.saving = false,
  });

  final CaptureDraft draft;
  final String? attachedProductId;
  final String? attachedProductName;
  final bool attachedProductIsUnique;
  final bool saving;

  CaptureState copyWith({
    CaptureDraft? draft,
    String? attachedProductId,
    String? attachedProductName,
    bool? attachedProductIsUnique,
    bool? saving,
  }) =>
      CaptureState(
        draft: draft ?? this.draft,
        attachedProductId: attachedProductId ?? this.attachedProductId,
        attachedProductName: attachedProductName ?? this.attachedProductName,
        attachedProductIsUnique:
            attachedProductIsUnique ?? this.attachedProductIsUnique,
        saving: saving ?? this.saving,
      );
}

enum SaveKind { enquiry, order }

class SaveResult {
  const SaveResult(this.kind, this.customerName);
  final SaveKind kind;
  final String customerName;
}

final captureControllerProvider =
    StateNotifierProvider.autoDispose<CaptureController, CaptureState>((ref) {
  return CaptureController(
    ref.watch(customersServiceProvider),
    ref.watch(enquiriesServiceProvider),
  );
});

class CaptureController extends StateNotifier<CaptureState> {
  CaptureController(this._customers, this._enquiries)
      : super(const CaptureState());

  final CustomersService _customers;
  final EnquiriesService _enquiries;

  void setText(String text) {
    final parsed = CaptureDraft.fromText(text);
    // Manual edits to name/phone survive re-parses of the message text.
    state = state.copyWith(
      draft: parsed.copyWith(
        name: state.draft.name ?? parsed.name,
        phone: state.draft.phone ?? parsed.phone,
      ),
    );
  }

  void editDraft(CaptureDraft draft) => state = state.copyWith(draft: draft);

  void attachProduct({
    required String id,
    required String name,
    required bool isUnique,
    required double price,
  }) {
    state = state.copyWith(
      attachedProductId: id,
      attachedProductName: name,
      attachedProductIsUnique: isUnique,
      draft: state.draft.copyWith(items: [
        DraftItem(name: name, qty: 1, price: price),
        ...state.draft.items,
      ]),
    );
  }

  Future<SaveResult> save() async {
    final draft = state.draft;
    state = state.copyWith(saving: true);
    try {
      final customer = await _customers.createOrLink(
        name: draft.name ?? 'Customer',
        phone: draft.phone,
      );

      final source = state.attachedProductId != null
          ? 'product'
          : (draft.raw.trim().isEmpty ? 'manual' : 'paste');

      if (draft.type == 'order' && draft.items.isNotEmpty) {
        await _enquiries.createOrder(
          customerId: customer.id!,
          items: draft.items,
          bookProductId:
              state.attachedProductIsUnique ? state.attachedProductId : null,
          productIds: [
            for (var i = 0; i < draft.items.length; i++)
              i == 0 ? state.attachedProductId : null,
          ],
          notes: draft.raw.trim().isEmpty ? null : draft.raw.trim(),
        );
        return SaveResult(SaveKind.order, customer.name);
      }

      await _enquiries.addEnquiry(
        customerId: customer.id!,
        productId: state.attachedProductId,
        source: source,
        message: draft.raw.trim(),
        intent: draft.intent,
        followUpDate: draft.followUpDate,
      );
      return SaveResult(SaveKind.enquiry, customer.name);
    } finally {
      if (mounted) state = state.copyWith(saving: false);
    }
  }
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze 2>&1 | tail -3`
Expected: no new issues (7 pre-existing baseline infos only).

- [ ] **Step 4: Commit**

```bash
git add lib/core/providers/auth_providers.dart lib/features/catalog/controller/products_provider.dart lib/features/enquiries/controller/enquiries_provider.dart lib/features/enquiries/controller/capture_provider.dart
git commit -m "feat(enquiries): auth-scoped enquiries and capture controllers"
```

---

### Task 6: Controller tests (fakes)

**Files:**
- Test: `test/features/enquiries/capture_controller_test.dart`

- [ ] **Step 1: Write the tests**

`test/features/enquiries/capture_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/customer.dart';
import 'package:orderly_app/features/enquiries/data/customers_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';

class FakeCustomersService implements CustomersService {
  final created = <Map<String, String?>>[];
  Customer? existing;

  @override
  Future<Customer> createOrLink({required String name, String? phone}) async {
    if (existing != null && phone != null && existing!.phone == phone) {
      return existing!;
    }
    created.add({'name': name, 'phone': phone});
    return Customer(id: 'c-new', name: name, phone: phone);
  }
}

class FakeEnquiriesService implements EnquiriesService {
  final enquiries = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];

  @override
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
  }) async {
    enquiries.add({
      'customer_id': customerId,
      'product_id': productId,
      'source': source,
      'status': followUpDate != null ? 'follow' : 'new',
    });
    return Enquiry.fromMap({'id': 'e-new', 'customer_id': customerId});
  }

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    orders.add({
      'customer_id': customerId,
      'lead_id': leadId,
      'items': items.length,
      'book': bookProductId,
    });
    return 'o-new';
  }

  @override
  Future<List<Enquiry>> fetchEnquiries() async => [];
  @override
  Future<Enquiry?> fetchById(String id) async => null;
  @override
  Future<void> updateEnquiry(String id, Map<String, dynamic> changes) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchLegacyMaps() async => [];
}

ProviderContainer makeContainer(
    FakeCustomersService customers, FakeEnquiriesService enquiries) {
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(customers),
    enquiriesServiceProvider.overrideWithValue(enquiries),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('save creates customer then enquiry with follow status', () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('This is Priya 9876543210, will confirm tomorrow');
    final result = await controller.save();

    expect(result.kind, SaveKind.enquiry);
    expect(customers.created.single['phone'], '9876543210');
    expect(enquiries.enquiries.single['status'], 'follow');
    expect(enquiries.enquiries.single['source'], 'paste');
  });

  test('save links existing customer by phone', () async {
    final customers = FakeCustomersService()
      ..existing = const Customer(id: 'c1', name: 'Priya', phone: '9876543210');
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('This is Priya 9876543210, price?');
    await controller.save();

    expect(customers.created, isEmpty);
    expect(enquiries.enquiries.single['customer_id'], 'c1');
  });

  test('order-type draft with items creates an order, books unique piece',
      () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.attachProduct(
        id: 'p1', name: 'Red Banarasi', isUnique: true, price: 5500);
    controller.setText('confirm order for 9876543210');
    final result = await controller.save();

    expect(result.kind, SaveKind.order);
    expect(enquiries.orders.single['book'], 'p1');
    expect(enquiries.enquiries, isEmpty);
  });

  test('manual field edits survive re-parse of message text', () async {
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('want 2 kurtis');
    controller.editDraft(
        c.read(captureControllerProvider).draft.copyWith(name: 'Anita'));
    controller.setText('want 2 kurtis tomorrow');

    expect(c.read(captureControllerProvider).draft.name, 'Anita');
  });
}
```

- [ ] **Step 2: Run, verify pass**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add test/features/enquiries/capture_controller_test.dart
git commit -m "test(enquiries): capture controller save paths and customer linking"
```

---

### Task 7: CaptureScreen + draft card

**Files:**
- Create: `lib/features/enquiries/presentation/capture_screen.dart`
- Create: `lib/features/enquiries/widgets/draft_card.dart`
- Test: `test/features/enquiries/capture_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/features/enquiries/capture_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/presentation/capture_screen.dart';

import 'capture_controller_test.dart'
    show FakeCustomersService, FakeEnquiriesService;

Widget wrap(Widget child, FakeEnquiriesService enquiries) {
  return ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(FakeCustomersService()),
      enquiriesServiceProvider.overrideWithValue(enquiries),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('typing fills the draft card and save button reads enquiry',
      (tester) async {
    await tester.pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));

    await tester.enterText(find.byKey(const Key('capture-input')),
        'This is Priya 9876543210, want 2 kurtis, will confirm tomorrow');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('Save enquiry'), findsOneWidget);
  });

  testWidgets('order text flips save button to Create order', (tester) async {
    await tester.pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));

    await tester.enterText(find.byKey(const Key('capture-input')),
        'Priya: confirm order 2 kurtis at ₹1500');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Create order'), findsOneWidget);
  });

  testWidgets('save creates enquiry and pops', (tester) async {
    final enquiries = FakeEnquiriesService();
    await tester.pumpWidget(wrap(const CaptureScreen(), enquiries));

    await tester.enterText(
        find.byKey(const Key('capture-input')), 'Priya wants a saree');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save enquiry'));
    await tester.pumpAndSettle();

    expect(enquiries.enquiries, hasLength(1));
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/enquiries/capture_screen_test.dart 2>&1 | tail -5`
Expected: FAIL — `capture_screen.dart` doesn't exist.

- [ ] **Step 3: Implement the draft card widget**

`lib/features/enquiries/widgets/draft_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../data/capture_draft.dart';

/// Live parse result. Rows are tappable so every parsed field is correctable.
class DraftCard extends StatelessWidget {
  const DraftCard({
    super.key,
    required this.draft,
    required this.attachedProductName,
    required this.onEditName,
    required this.onEditPhone,
    required this.onEditFollowUp,
    required this.onRemoveItem,
  });

  final CaptureDraft draft;
  final String? attachedProductName;
  final VoidCallback onEditName;
  final VoidCallback onEditPhone;
  final VoidCallback onEditFollowUp;
  final void Function(int index) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                draft.type == 'order' ? 'Order draft' : 'Enquiry draft',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _row(Icons.person_outline, draft.name ?? 'Customer',
              onTap: onEditName, key: const Key('draft-name')),
          _row(Icons.phone_outlined, draft.phone ?? 'Add phone',
              muted: draft.phone == null,
              onTap: onEditPhone,
              key: const Key('draft-phone')),
          if (attachedProductName != null)
            _row(Icons.storefront_outlined, attachedProductName!),
          for (var i = 0; i < draft.items.length; i++)
            _row(
              Icons.shopping_bag_outlined,
              '${draft.items[i].qty} × ${draft.items[i].name}'
              '${draft.items[i].price != null ? ' @ ${Money.inr(draft.items[i].price!)}' : ''}',
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onRemoveItem(i),
              ),
            ),
          _row(
            Icons.event_outlined,
            draft.followUpDate == null
                ? 'No follow-up'
                : 'Follow up ${draft.followUpDate!.day}/${draft.followUpDate!.month}',
            muted: draft.followUpDate == null,
            onTap: onEditFollowUp,
            key: const Key('draft-followup'),
          ),
        ],
      ),
    );
  }

  Widget _row(
    IconData icon,
    String text, {
    bool muted = false,
    VoidCallback? onTap,
    Widget? trailing,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color:
                      muted ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement CaptureScreen**

`lib/features/enquiries/presentation/capture_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controller/capture_provider.dart';
import '../controller/enquiries_provider.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    super.key,
    this.productId,
    this.productName,
    this.productIsUnique = false,
    this.productPrice = 0,
  });

  /// When set, the capture starts with this product attached (product-first
  /// enquiry from the catalog).
  final String? productId;
  final String? productName;
  final bool productIsUnique;
  final double productPrice;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _text = TextEditingController();
  final _speech = SpeechToText();
  Timer? _debounce;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    if (widget.productId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(captureControllerProvider.notifier).attachProduct(
              id: widget.productId!,
              name: widget.productName ?? 'Piece',
              isUnique: widget.productIsUnique,
              price: widget.productPrice,
            );
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(captureControllerProvider.notifier).setText(_text.text);
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _text.text = text;
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available')),
      );
      return;
    }
    setState(() => _listening = true);
    _speech.listen(onResult: (r) => _text.text = r.recognizedWords);
  }

  Future<void> _editField({
    required String title,
    required String initial,
    required void Function(String value) onSubmit,
    TextInputType keyboard = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller, keyboardType: keyboard, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) onSubmit(value);
  }

  Future<void> _pickFollowUp() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final controller = ref.read(captureControllerProvider.notifier);
    final draft = ref.read(captureControllerProvider).draft;
    controller.editDraft(
        draft.copyWith(followUpDate: picked, intent: 'follow_up'));
  }

  Future<void> _save() async {
    final controller = ref.read(captureControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await controller.save();
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ref.read(enquiriesControllerProvider.notifier).load();
      messenger.showSnackBar(SnackBar(
        content: Text(result.kind == SaveKind.order
            ? 'Order created for ${result.customerName}'
            : 'Enquiry saved for ${result.customerName}'),
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final draft = state.draft;
    final controller = ref.read(captureControllerProvider.notifier);
    final hasContent = !draft.isEmpty || state.attachedProductId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Capture')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            key: const Key('capture-input'),
            controller: _text,
            maxLines: 6,
            autofocus: true,
            decoration: InputDecoration(
              hintText:
                  'Paste the WhatsApp chat, speak, or type what the customer wants…',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
              TextButton.icon(
                onPressed: _toggleMic,
                icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                    size: 18,
                    color: _listening ? AppColors.danger : null),
                label: Text(_listening ? 'Stop' : 'Speak'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasContent) ...[
            DraftCard(
              draft: draft,
              attachedProductName: state.attachedProductName,
              onEditName: () => _editField(
                title: 'Customer name',
                initial: draft.name ?? '',
                onSubmit: (v) =>
                    controller.editDraft(draft.copyWith(name: v)),
              ),
              onEditPhone: () => _editField(
                title: 'Phone',
                initial: draft.phone ?? '',
                keyboard: TextInputType.phone,
                onSubmit: (v) =>
                    controller.editDraft(draft.copyWith(phone: v)),
              ),
              onEditFollowUp: _pickFollowUp,
              onRemoveItem: (i) {
                final items = [...draft.items]..removeAt(i);
                controller.editDraft(draft.copyWith(items: items));
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: draft.type == 'order' && draft.items.isNotEmpty
                  ? 'Create order'
                  : 'Save enquiry',
              loading: state.saving,
              onPressed: _save,
            ),
          ],
        ],
      ),
    );
  }
}
```

Add the missing imports the code above needs: `import 'package:orderly_app/core/theme/app_spacing.dart';` covers `AppRadius`; `import '../widgets/draft_card.dart';` for `DraftCard`.

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/presentation/capture_screen.dart lib/features/enquiries/widgets/draft_card.dart test/features/enquiries/capture_screen_test.dart
git commit -m "feat(enquiries): paste-first CaptureScreen with live draft card"
```

---

### Task 8: Enquiries screen (buckets, search, cards)

**Files:**
- Create: `lib/features/enquiries/presentation/enquiries_screen.dart`
- Create: `lib/features/enquiries/widgets/enquiry_card.dart`
- Test: `test/features/enquiries/enquiries_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/features/enquiries/enquiries_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiries_screen.dart';

import 'capture_controller_test.dart' show FakeEnquiriesService;

class SeededEnquiriesService extends FakeEnquiriesService {
  SeededEnquiriesService(this.seed);
  final List<Enquiry> seed;
  @override
  Future<List<Enquiry>> fetchEnquiries() async => seed;
}

void main() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  Widget app(List<Enquiry> seed) => ProviderScope(
        overrides: [
          enquiriesServiceProvider
              .overrideWithValue(SeededEnquiriesService(seed)),
        ],
        child: const MaterialApp(home: EnquiriesScreen()),
      );

  testWidgets('groups enquiries into buckets', (tester) async {
    await tester.pumpWidget(app([
      Enquiry.fromMap({
        'id': 'e1',
        'status': 'follow',
        'follow_up_date': yesterday.toIso8601String(),
        'customers': {'name': 'Priya'},
      }),
      Enquiry.fromMap({
        'id': 'e2',
        'status': 'new',
        'customers': {'name': 'Anita'},
      }),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Anita'), findsOneWidget);
  });

  testWidgets('search filters by customer name', (tester) async {
    await tester.pumpWidget(app([
      Enquiry.fromMap({
        'id': 'e1',
        'status': 'new',
        'customers': {'name': 'Priya'},
      }),
      Enquiry.fromMap({
        'id': 'e2',
        'status': 'new',
        'customers': {'name': 'Anita'},
      }),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('enquiry-search')), 'pri');
    await tester.pumpAndSettle();

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('empty state renders', (tester) async {
    await tester.pumpWidget(app([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No enquiries'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/enquiries/enquiries_screen_test.dart 2>&1 | tail -5`
Expected: FAIL — screen doesn't exist.

- [ ] **Step 3: Implement enquiry card**

`lib/features/enquiries/widgets/enquiry_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../data/enquiry.dart';

class EnquiryCard extends StatelessWidget {
  const EnquiryCard({super.key, required this.enquiry, required this.onTap});

  final Enquiry enquiry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = enquiry.followUpDate;
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Row(
          children: [
            if (enquiry.productImage != null)
              SizedBox(
                width: 52,
                height: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ProductImage(
                      path: enquiry.productImage, cacheWidth: 150),
                ),
              )
            else
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceMuted,
                child: Text(
                  (enquiry.customerName ?? 'C')[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enquiry.customerName ?? 'Customer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  if ((enquiry.message ?? '').isNotEmpty)
                    Text(
                      enquiry.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (due != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${due.day}/${due.month}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement EnquiriesScreen**

`lib/features/enquiries/presentation/enquiries_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/enquiries_provider.dart';
import '../data/enquiry.dart';
import '../widgets/enquiry_card.dart';
import 'enquiry_detail_screen.dart';

class EnquiriesScreen extends ConsumerStatefulWidget {
  const EnquiriesScreen({super.key});

  @override
  ConsumerState<EnquiriesScreen> createState() => _EnquiriesScreenState();
}

class _EnquiriesScreenState extends ConsumerState<EnquiriesScreen> {
  String _search = '';

  static const _bucketOrder = [
    (EnquiryBucket.overdue, 'Overdue'),
    (EnquiryBucket.today, 'Today'),
    (EnquiryBucket.upcoming, 'Upcoming'),
    (EnquiryBucket.fresh, 'New'),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(enquiriesControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text(
                'Enquiries',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                key: const Key('enquiry-search'),
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search customers or messages',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load enquiries'),
                      TextButton(
                        onPressed: () => ref
                            .read(enquiriesControllerProvider.notifier)
                            .load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (all) {
                  final filtered = _search.isEmpty
                      ? all
                      : all.where((e) {
                          final hay =
                              '${e.customerName ?? ''} ${e.message ?? ''}'
                                  .toLowerCase();
                          return hay.contains(_search);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text(
                        'No enquiries yet.\nTap + to capture your first one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  final now = DateTime.now();
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(enquiriesControllerProvider.notifier).load(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, 96),
                      children: [
                        for (final (bucket, label) in _bucketOrder)
                          ..._section(label,
                              [for (final e in filtered) if (e.bucket(now) == bucket) e]),
                      ],
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

  List<Widget> _section(String label, List<Enquiry> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(
            top: AppSpacing.md, bottom: AppSpacing.sm),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary),
        ),
      ),
      for (final e in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: EnquiryCard(
            enquiry: e,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EnquiryDetailScreen(enquiry: e)),
            ),
          ),
        ),
    ];
  }
}
```

Note: `EnquiryDetailScreen` arrives in Task 9. To keep this task compiling, create the stub file `lib/features/enquiries/presentation/enquiry_detail_screen.dart` now:

```dart
import 'package:flutter/material.dart';

import '../data/enquiry.dart';

class EnquiryDetailScreen extends StatelessWidget {
  const EnquiryDetailScreen({super.key, required this.enquiry});
  final Enquiry enquiry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(enquiry.customerName ?? 'Enquiry')));
  }
}
```

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/presentation/enquiries_screen.dart lib/features/enquiries/presentation/enquiry_detail_screen.dart lib/features/enquiries/widgets/enquiry_card.dart test/features/enquiries/enquiries_screen_test.dart
git commit -m "feat(enquiries): bucketed enquiries screen with search"
```

---

### Task 9: Enquiry detail — convert to order, reschedule, contact

**Files:**
- Modify: `lib/features/enquiries/presentation/enquiry_detail_screen.dart` (replace stub)
- Test: `test/features/enquiries/enquiry_detail_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/features/enquiries/enquiry_detail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiry_detail_screen.dart';

import 'capture_controller_test.dart' show FakeEnquiriesService;

class RecordingEnquiriesService extends FakeEnquiriesService {
  String? convertedLeadId;
  String? bookedProductId;

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    convertedLeadId = leadId;
    bookedProductId = bookProductId;
    return 'o1';
  }
}

void main() {
  final enquiry = Enquiry.fromMap({
    'id': 'e1',
    'customer_id': 'c1',
    'product_id': 'p1',
    'status': 'new',
    'message': 'Wants the red saree',
    'customers': {'name': 'Priya', 'phone': '9876543210'},
    'products': {
      'name': 'Red Banarasi',
      'images': <String>[],
      'is_unique': true,
      'piece_status': 'available',
    },
  });

  testWidgets('convert to order books the unique piece', (tester) async {
    final service = RecordingEnquiriesService();
    await tester.pumpWidget(ProviderScope(
      overrides: [enquiriesServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: EnquiryDetailScreen(enquiry: enquiry)),
    ));

    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(service.convertedLeadId, 'e1');
    expect(service.bookedProductId, 'p1');
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/enquiries/enquiry_detail_test.dart 2>&1 | tail -5`
Expected: FAIL — stub has no 'Convert to order'.

- [ ] **Step 3: Implement the detail screen**

Replace the stub `lib/features/enquiries/presentation/enquiry_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/enquiries_provider.dart';
import '../data/capture_draft.dart';
import '../data/enquiry.dart';

class EnquiryDetailScreen extends ConsumerWidget {
  const EnquiryDetailScreen({super.key, required this.enquiry});

  final Enquiry enquiry;

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the app')),
      );
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: enquiry.followUpDate ??
          DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(enquiriesControllerProvider.notifier)
          .reschedule(enquiry.id!, picked);
      messenger.showSnackBar(SnackBar(
          content: Text('Follow-up set for ${picked.day}/${picked.month}')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not update. Try again.')));
    }
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Convert to order?'),
        content: Text(enquiry.productIsUnique
            ? 'This books ${enquiry.productName ?? 'the piece'} so it cannot be sold twice.'
            : 'Creates an order for ${enquiry.customerName ?? 'this customer'}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(enquiriesControllerProvider.notifier).convertToOrder(
        enquiry,
        [
          DraftItem(
              name: enquiry.productName ?? 'Item',
              qty: 1,
              price: enquiry.productPrice),
        ],
      );
      if (!context.mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Order created')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not convert. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = enquiry.customerPhone;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(enquiry.customerName ?? 'Enquiry')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if ((enquiry.message ?? '').isNotEmpty)
            AppCard(
              child: Text(enquiry.message!,
                  style: const TextStyle(height: 1.5)),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(enquiry.followUpDate == null
                      ? 'No follow-up scheduled'
                      : 'Follow up ${enquiry.followUpDate!.day}/${enquiry.followUpDate!.month}'),
                  trailing: TextButton(
                    onPressed: () => _reschedule(context, ref),
                    child: const Text('Change'),
                  ),
                ),
                if (phone != null && phone.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openUri(
                              context, Uri.parse('https://wa.me/91$phone')),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openUri(context, Uri.parse('tel:$phone')),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: const Text('Call'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Convert to order',
            onPressed: () => _convert(context, ref),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(enquiriesControllerProvider.notifier)
                    .markLost(enquiry.id!);
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              } catch (_) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Could not update. Try again.')));
              }
            },
            child: const Text('Mark as lost',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run all enquiries tests**

Run: `flutter test test/features/enquiries/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/presentation/enquiry_detail_screen.dart test/features/enquiries/enquiry_detail_test.dart
git commit -m "feat(enquiries): detail screen with convert-to-order booking and contact actions"
```

---

### Task 10: Nav/FAB rework + catalog "Create enquiry"

**Files:**
- Modify: `lib/main.dart` (FAB routes to CaptureScreen; screens list swaps `LeadsScreen` → `EnquiriesScreen`)
- Modify: `lib/shared/widgets/app_bottom_nav.dart` (label "Leads" → "Enquiries")
- Modify: `lib/features/catalog/presentation/product_detail_screen.dart` (add "Create enquiry" button)

- [ ] **Step 1: Rewire main.dart**

In `lib/main.dart`:
- Replace import of `features/leads/presentation/leads_screen.dart` with `features/enquiries/presentation/enquiries_screen.dart`.
- In `_screens`, replace `const LeadsScreen()` with `const EnquiriesScreen()`.
- Replace the FAB `showModalBottomSheet(... AddEntryScreen ...)` branch with:

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const CaptureScreen()),
);
```

with import `package:orderly_app/features/enquiries/presentation/capture_screen.dart`. Keep the `currentIndex == 3` → `ProductFormScreen` branch unchanged.

- [ ] **Step 2: Rename nav label**

In `lib/shared/widgets/app_bottom_nav.dart` change `navItem(Icons.people_alt_rounded, "Leads", 1)` to `navItem(Icons.people_alt_rounded, "Enquiries", 1)`.

- [ ] **Step 3: Catalog product-first enquiry**

In `lib/features/catalog/presentation/product_detail_screen.dart`, inside the `build` method's `ListView` children, after the `AppCard` with the status/stock control, add:

```dart
const SizedBox(height: AppSpacing.lg),
AppPrimaryButton(
  label: 'Create enquiry',
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CaptureScreen(
        productId: p.id,
        productName: p.name,
        productIsUnique: p.isUnique,
        productPrice: p.price,
      ),
    ),
  ),
),
```

with imports `package:orderly_app/shared/widgets/app_primary_button.dart` and `package:orderly_app/features/enquiries/presentation/capture_screen.dart`.

- [ ] **Step 4: Verify**

Run: `flutter analyze 2>&1 | tail -3` → no new issues.
Run: `flutter test 2>&1 | tail -3` → all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/shared/widgets/app_bottom_nav.dart lib/features/catalog/presentation/product_detail_screen.dart
git commit -m "feat(nav): FAB opens CaptureScreen, Enquiries tab, product-first enquiry from catalog"
```

---

### Task 11: Legacy compat shim — re-back LeadsController, notifications, navigation

Surviving legacy consumers (`dashboard_screen`, `orders_provider`, `order_detail_screen`, `notifications_screen`, `splash_screen`, `app_header`, `order_card`) read `leadsControllerProvider` as `List<Map<String, dynamic>>` and call `loadLeads()`, `markDone()`, `updateOrderStatus()`, `updateOrderItems()`. Keep the provider; gut the internals.

**Files:**
- Rewrite: `lib/features/leads/controller/leads_controller.dart`
- Modify: `lib/core/services/notification_service.dart` (line ~361 + ~370: `LeadsService().fetchLeads()` → new adapter; line ~529 `isClosed` already checks `"closed"` which the adapter emits — no change)
- Modify: `lib/core/services/lead_navigation_service.dart` (notification tap → `EnquiryDetailScreen`)
- Delete: `lib/core/services/leads_service.dart`

- [ ] **Step 1: Rewrite LeadsController as a shim**

`lib/features/leads/controller/leads_controller.dart` (full replacement):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/notification_service.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Legacy-shaped state for pre-spec screens (Dashboard, Orders, notifications).
/// Backed by the enquiries data layer; retired when stages 4/7 rebuild them.
final leadsControllerProvider =
    StateNotifierProvider<LeadsController, List<Map<String, dynamic>>>((ref) {
      return LeadsController(EnquiriesService());
    });

class LeadsController extends StateNotifier<List<Map<String, dynamic>>> {
  LeadsController(this._service) : super([]);

  final EnquiriesService _service;
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> loadLeads() async {
    try {
      state = await _service.fetchLegacyMaps();
      await NotificationService.syncLeadNotifications(leads: state);
    } catch (_) {
      // Keep previous state on failure; surviving legacy screens have no
      // error surface. New screens handle errors properly.
    }
  }

  /// Notifications screen "mark done": converts the enquiry to an order.
  Future<void> markDone(Map<String, dynamic> lead) async {
    try {
      final customerId = lead['customer_id']?.toString();
      if (customerId == null) return;
      await _service.createOrder(
        customerId: customerId,
        leadId: lead['id'].toString(),
        items: const [DraftItem(name: 'Item', qty: 1)],
      );
      await loadLeads();
    } catch (_) {}
  }

  /// Order detail status stepper. Legacy statuses map onto the new enum.
  Future<void> updateOrderStatus(
    Map<String, dynamic> order,
    String status,
  ) async {
    const map = {
      'pending': 'pending',
      'processing': 'packed',
      'completed': 'delivered',
      'packed': 'packed',
      'shipped': 'shipped',
      'delivered': 'delivered',
    };
    final orderId = (order['order_id'] ?? order['id'])?.toString();
    final mapped = map[status];
    if (orderId == null || mapped == null) return;
    try {
      await _client
          .from('orders')
          .update({
            'status': mapped,
            if (mapped == 'delivered')
              'delivered_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      await loadLeads();
    } catch (_) {}
  }

  /// Order detail item editor, re-pointed at real order_items.
  Future<void> updateOrderItems(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
  ) async {
    final orderId = (order['order_id'] ?? order['id'])?.toString();
    final userId = _client.auth.currentUser?.id;
    if (orderId == null || userId == null) return;

    await _client.from('order_items').delete().eq('order_id', orderId);
    double subtotal = 0;
    final rows = items.map((item) {
      final qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
      final price = double.tryParse(item['price']?.toString() ?? '') ?? 0;
      subtotal += price * qty;
      return {
        'user_id': userId,
        'order_id': orderId,
        'name': (item['product_name'] ?? item['name'] ?? 'Item').toString(),
        'unit_price': price,
        'qty': qty,
        'line_total': price * qty,
      };
    }).toList();
    if (rows.isNotEmpty) {
      await _client.from('order_items').insert(rows);
    }
    await _client
        .from('orders')
        .update({'subtotal': subtotal, 'grand_total': subtotal})
        .eq('id', orderId);
    await loadLeads();
  }
}
```

Note: legacy methods `addLead`, `editLead`, `deleteLead`, `restoreLead`, `followUp` are dropped — their only callers are files deleted in Task 12. If `flutter analyze` reports another surviving caller, port that call to the new controllers instead of resurrecting the method.

- [ ] **Step 2: Rewire notification engine fetch**

In `lib/core/services/notification_service.dart`:
- Replace `import ... leads_service.dart` with `import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';`
- Replace both `await LeadsService().fetchLeads()` occurrences (lines ~361, ~370) with `await EnquiriesService().fetchLegacyMaps()`.
No other changes — the engine's keys (`status == "follow"`, `follow_up_date`, `name`, `msg`, `"closed"`) all exist in the adapter shape.

- [ ] **Step 3: Rewire notification tap navigation**

`lib/core/services/lead_navigation_service.dart`: replace the `EntryDetailScreen(entry: normalizedLead)` push with:

```dart
final enquiry = await EnquiriesService().fetchById(leadId);
if (enquiry == null) return;
navigator.push(
  MaterialPageRoute(builder: (_) => EnquiryDetailScreen(enquiry: enquiry)),
);
```

adjusting imports accordingly (read the file first; keep its navigator-resolution logic).

- [ ] **Step 4: Delete leads_service.dart, verify, commit**

```bash
rm lib/core/services/leads_service.dart
flutter analyze 2>&1 | tail -5
```

Expected: errors ONLY in files scheduled for deletion in Task 12 (`add_entry_screen.dart`, `whatsapp_input_screen.dart`, `entry_detail_screen.dart`, `leads_screen.dart` tree). If any OTHER file errors, fix it before proceeding.

```bash
flutter test 2>&1 | tail -3
git add -A lib/core/services lib/features/leads/controller
git commit -m "refactor(leads): re-back legacy provider with enquiries data layer"
```

---

### Task 12: Delete legacy capture + leads presentation

**Files:**
- Delete: `lib/shared/components/add_entry_selector.dart`, `lib/shared/components/add_entry_screen.dart`, `lib/shared/components/entry_detail_screen.dart`
- Delete: `lib/features/whatsapp/` (whole feature)
- Delete: `lib/features/leads/presentation/leads_screen.dart`, `lib/features/leads/widgets/` (all six widgets)
- Delete: `lib/core/utils/message_parser.dart`, `lib/core/utils/lead_ai.dart`, `lib/core/utils/leads_sorter.dart` — ONLY if `grep -rn` shows no surviving importers; otherwise leave and note
- Delete: `lib/app/app_intro_screen copy.dart` (stray duplicate, drive-by cleanup)

- [ ] **Step 1: Delete and check each group**

```bash
rm lib/shared/components/add_entry_selector.dart lib/shared/components/add_entry_screen.dart lib/shared/components/entry_detail_screen.dart
rm -rf lib/features/whatsapp
rm lib/features/leads/presentation/leads_screen.dart
rm -rf lib/features/leads/widgets
rm "lib/app/app_intro_screen copy.dart"
grep -rln "message_parser\|lead_ai\|leads_sorter" lib test
```

If the grep is empty: `rm lib/core/utils/message_parser.dart lib/core/utils/lead_ai.dart lib/core/utils/leads_sorter.dart` and delete their tests if any exist under `test/`. If not empty, fix the importer (it should not exist — investigate before deleting).

- [ ] **Step 2: Fix any dangling imports**

Run: `flutter analyze 2>&1 | tail -10`
Likely dangling importers to fix: any file still importing the deleted screens (search: `grep -rln "add_entry\|entry_detail_screen\|whatsapp_input\|leads_screen\|lead_card" lib test`). Update or delete those references — e.g. old widget tests referencing deleted widgets get deleted too.

- [ ] **Step 3: Full verify**

Run: `flutter analyze` → **0 issues** (the 7-info baseline lived in deleted files).
Run: `flutter test 2>&1 | tail -3` → all pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete legacy capture screens, leads UI, and rule utils"
```

(`git add -A` is safe here ONLY after `git status` confirms nothing foreign is dirty — this task is purely deletions plus Task-11/12 edits. Check first.)

---

### Task 13: Final gate + review

- [ ] **Step 1: Full local gate**

```bash
flutter analyze
flutter test
```

Expected: 0 analyze issues; all tests pass (catalog 17 + enquiries new suites + legacy survivors).

- [ ] **Step 2: Supabase advisors**

Run `mcp__claude_ai_Supabase__get_advisors` (security) → no new findings vs the 8 known baseline WARNs.

- [ ] **Step 3: Code review**

Dispatch the code-reviewer agent over `git diff <first-task-commit>^..HEAD`. Fix verified findings; re-run gate.

- [ ] **Step 4: Device smoke test checklist (user-run)**

`flutter run` → login → FAB from Home → paste a WhatsApp-style text → draft card fills → save enquiry → appears in Enquiries bucket → open detail → reschedule → convert to order → order appears in Orders tab → catalog piece shows Booked → notifications still fire.
