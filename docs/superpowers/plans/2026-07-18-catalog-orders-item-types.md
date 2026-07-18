# Catalog & Orders — Item Types + Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four item types (product/service/digital/other) with icons + accents, and turn the catalog and order flows into image-card experiences.

**Architecture:** A single `ItemType` registry drives every type-aware surface (badges, placeholders, filters) so new types are one entry, no widget edits. Type is stored on `products` (+ per-type fields) and snapshotted onto `order_items` for display. The order lifecycle is unchanged. Catalog filtering is a pure function over the already-loaded, user-scoped product list.

**Tech Stack:** Flutter, Riverpod (StateNotifier), Supabase (Postgres + RLS), `pdf` package for invoices. Tests: `flutter_test`.

**Design spec:** `docs/superpowers/specs/2026-07-18-catalog-orders-item-types-design.md`

**Conventions in this repo:**
- Colors come from `AppColors`, spacing/radius from `AppSpacing`/`AppRadius`. Never hardcode `Color(0x..)` in widgets.
- Run one test file: `flutter test test/path/to/file_test.dart`
- Run the analyzer: `flutter analyze`
- Commit style: `feat(scope): summary` / `test(scope): summary`, ending with the Co-Authored-By trailer.

---

## Task 1: ItemType registry + color tokens

**Files:**
- Modify: `lib/core/theme/app_colors.dart`
- Create: `lib/features/catalog/data/item_type.dart`
- Test: `test/features/catalog/item_type_test.dart`

- [ ] **Step 1: Add type color tokens to `AppColors`**

Add inside the `AppColors` class (after the `border` line):

```dart
  // Item type accents + soft-tint badge backgrounds + placeholder gradients
  static const Color typeProductAccent = Color(0xFF5B4FE9);
  static const Color typeProductTint = Color(0xFFECEBFD);
  static const Color typeProductGradientEnd = Color(0xFFDEDBFA);

  static const Color typeServiceAccent = Color(0xFF0D9488);
  static const Color typeServiceTint = Color(0xFFE0F2F0);
  static const Color typeServiceGradientEnd = Color(0xFFCFE9E6);

  static const Color typeDigitalAccent = Color(0xFF7C3AED);
  static const Color typeDigitalTint = Color(0xFFF1EBFE);
  static const Color typeDigitalGradientEnd = Color(0xFFE7D9FC);

  static const Color typeOtherAccent = Color(0xFF64748B);
  static const Color typeOtherTint = Color(0xFFEEF1F5);
  static const Color typeOtherGradientEnd = Color(0xFFE2E7EE);
```

- [ ] **Step 2: Write the failing test**

Create `test/features/catalog/item_type_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';

void main() {
  group('ItemType', () {
    test('exposes the four supported types in order', () {
      expect(ItemType.values.map((t) => t.id).toList(),
          ['product', 'service', 'digital', 'other']);
    });

    test('fromId matches a known id', () {
      expect(ItemType.fromId('service'), ItemType.service);
      expect(ItemType.service.label, 'Service');
      expect(ItemType.service.accent, AppColors.typeServiceAccent);
    });

    test('fromId falls back to other for null or unknown', () {
      expect(ItemType.fromId(null), ItemType.other);
      expect(ItemType.fromId('subscription'), ItemType.other);
    });

    test('every type has a two-stop gradient', () {
      for (final t in ItemType.values) {
        expect(t.gradient.length, 2);
        expect(t.icon, isA<IconData>());
      }
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/catalog/item_type_test.dart`
Expected: FAIL — `item_type.dart` does not exist.

- [ ] **Step 4: Create the registry**

Create `lib/features/catalog/data/item_type.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

/// Registry of catalog item types. Every type-aware surface (badge, placeholder,
/// filter) reads from here — adding a new type (subscription, rental, bundle …)
/// is a single entry with no widget changes.
class ItemType {
  const ItemType({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
    required this.tint,
    required this.gradient,
  });

  final String id; // persisted db value
  final String label;
  final IconData icon;
  final Color accent; // icon + label color
  final Color tint; // badge background
  final List<Color> gradient; // placeholder background (2 stops)

  static const product = ItemType(
    id: 'product',
    label: 'Product',
    icon: Icons.inventory_2_outlined,
    accent: AppColors.typeProductAccent,
    tint: AppColors.typeProductTint,
    gradient: [AppColors.typeProductTint, AppColors.typeProductGradientEnd],
  );
  static const service = ItemType(
    id: 'service',
    label: 'Service',
    icon: Icons.handyman_outlined,
    accent: AppColors.typeServiceAccent,
    tint: AppColors.typeServiceTint,
    gradient: [AppColors.typeServiceTint, AppColors.typeServiceGradientEnd],
  );
  static const digital = ItemType(
    id: 'digital',
    label: 'Digital Product',
    icon: Icons.devices_outlined,
    accent: AppColors.typeDigitalAccent,
    tint: AppColors.typeDigitalTint,
    gradient: [AppColors.typeDigitalTint, AppColors.typeDigitalGradientEnd],
  );
  static const other = ItemType(
    id: 'other',
    label: 'Other',
    icon: Icons.category_outlined,
    accent: AppColors.typeOtherAccent,
    tint: AppColors.typeOtherTint,
    gradient: [AppColors.typeOtherTint, AppColors.typeOtherGradientEnd],
  );

  static const List<ItemType> values = [product, service, digital, other];

  static ItemType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => other);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/catalog/item_type_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/app_colors.dart lib/features/catalog/data/item_type.dart test/features/catalog/item_type_test.dart
git commit -m "feat(catalog): add ItemType registry + type color tokens"
```

---

## Task 2: Migration — type columns + RPC snapshot

**Files:**
- Create: `supabase/migrations/0030_item_types.sql`

No automated test (SQL). Verify by applying to a scratch DB (or via the Supabase MCP against a branch) and re-running to confirm idempotency.

- [ ] **Step 1: Write the migration — table columns**

Create `supabase/migrations/0030_item_types.sql` starting with:

```sql
-- Item types: products gain a type + per-type fields; order_items snapshot the
-- type for badge display. Lifecycle is unchanged. Idempotent.

alter table public.products
  add column if not exists type text not null default 'product',
  add column if not exists category text,
  add column if not exists duration text,
  add column if not exists delivery_method text;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_type_check'
  ) then
    alter table public.products
      add constraint products_type_check
      check (type in ('product','service','digital','other'));
  end if;
end $$;

alter table public.order_items
  add column if not exists item_type text not null default 'product';

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'order_items_item_type_check'
  ) then
    alter table public.order_items
      add constraint order_items_item_type_check
      check (item_type in ('product','service','digital','other'));
  end if;
end $$;

create index if not exists idx_products_user_type
  on public.products(user_id, type);
```

- [ ] **Step 2: Add the RPC v4 to the same file**

Open `supabase/migrations/0020_orders_pricing_lifecycle.sql` and copy the **entire**
`create function public.create_order_with_items( … ) … $$;` block (lines 45–143) and
paste it at the end of `0030_item_types.sql`. Then make exactly two changes to the pasted block:

1. Change the first line from `create function public.create_order_with_items(` to
   `create or replace function public.create_order_with_items(`.
2. Replace this insert statement:

```sql
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
```

with:

```sql
    insert into order_items
      (user_id, order_id, product_id, name, image_url, item_type, unit_price, gst_rate, qty, line_total)
    values (
      auth.uid(),
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(nullif(v_item->>'name', ''), 'Item'),
      v_item->>'image_url',
      coalesce(nullif(v_item->>'item_type', ''), 'product'),
      v_price,
      coalesce((v_item->>'gst_rate')::numeric, 0),
      v_qty,
      v_price * v_qty
    );
```

Leave the parameter signature, `security definer`, and grants unchanged — the type
rides inside `p_items`, so `create or replace` needs no drop/re-grant.

- [ ] **Step 3: Verify idempotent apply**

Apply the migration to a scratch/branch DB, then apply it a second time. Expected:
both runs succeed; the second is a no-op (no duplicate columns/constraints/index).
Confirm `create_order_with_items` still exists with its original argument list.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0030_item_types.sql
git commit -m "feat(db): add item type columns + snapshot type into order_items"
```

---

## Task 3: Product model — type + per-type fields

**Files:**
- Modify: `lib/features/catalog/data/product.dart`
- Test: `test/features/catalog/product_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append inside the `group('Product', ...)` block in `test/features/catalog/product_test.dart`:

```dart
    test('round-trips type + per-type fields', () {
      final original = Product(
        name: 'Home Cleaning',
        price: 899,
        type: 'service',
        category: 'Housekeeping',
        duration: '90 min',
        deliveryMethod: null,
      );
      final restored = Product.fromMap(original.toMap());
      expect(restored.type, 'service');
      expect(restored.category, 'Housekeeping');
      expect(restored.duration, '90 min');
      expect(restored.itemType, ItemType.service);
    });

    test('defaults type to product when absent', () {
      final p = Product.fromMap({'name': 'X'});
      expect(p.type, 'product');
      expect(p.itemType, ItemType.product);
    });
```

Add this import at the top of the test file:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/product_test.dart`
Expected: FAIL — `Product` has no `type`/`category`/`duration`/`deliveryMethod`/`itemType`.

- [ ] **Step 3: Add the fields to `Product`**

In `lib/features/catalog/data/product.dart`:

Add the import at the top:

```dart
import 'item_type.dart';
```

Add to the constructor (after `this.active = true,`):

```dart
    this.type = 'product',
    this.category,
    this.duration,
    this.deliveryMethod,
```

Add the fields (after `final bool active;`):

```dart
  final String type;
  final String? category;
  final String? duration;
  final String? deliveryMethod;

  ItemType get itemType => ItemType.fromId(type);
```

Extend `copyWith` — change its signature and body to carry the new fields:

```dart
  Product copyWith({
    int? qtyOnHand,
    String? pieceStatus,
    String? type,
    String? category,
    String? duration,
    String? deliveryMethod,
  }) {
    return Product(
      id: id,
      name: name,
      description: description,
      sku: sku,
      images: images,
      price: price,
      unit: unit,
      gstRate: gstRate,
      isUnique: isUnique,
      pieceStatus: pieceStatus ?? this.pieceStatus,
      qtyOnHand: qtyOnHand ?? this.qtyOnHand,
      active: active,
      createdAt: createdAt,
      type: type ?? this.type,
      category: category ?? this.category,
      duration: duration ?? this.duration,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
    );
  }
```

In `fromMap`, add before the closing `);`:

```dart
      type: (map['type'] ?? 'product').toString(),
      category: map['category']?.toString(),
      duration: map['duration']?.toString(),
      deliveryMethod: map['delivery_method']?.toString(),
```

In `toMap`, add before the closing `};`:

```dart
        'type': type,
        'category': category,
        'duration': duration,
        'delivery_method': deliveryMethod,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/product_test.dart`
Expected: PASS (all Product tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/data/product.dart test/features/catalog/product_test.dart
git commit -m "feat(catalog): add type + per-type fields to Product"
```

> Note: `ProductsService` needs no change — `fetchProducts` uses `select()` (all columns),
> `addProduct` serializes via `toMap()`, and `updateProduct` takes an explicit changes map.

---

## Task 4: TypeBadge widget

**Files:**
- Create: `lib/features/catalog/widgets/type_badge.dart`
- Test: `test/features/catalog/type_badge_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/type_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows label + icon for the type', (tester) async {
    await tester.pumpWidget(_wrap(const TypeBadge(type: ItemType.service)));
    expect(find.text('Service'), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
  });

  testWidgets('compact hides the label but keeps the icon', (tester) async {
    await tester.pumpWidget(
        _wrap(const TypeBadge(type: ItemType.digital, compact: true)));
    expect(find.text('Digital Product'), findsNothing);
    expect(find.byIcon(Icons.devices_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/type_badge_test.dart`
Expected: FAIL — `type_badge.dart` does not exist.

- [ ] **Step 3: Create the widget**

Create `lib/features/catalog/widgets/type_badge.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../data/item_type.dart';

/// Soft-tint pill for an item type: tinted background, accent icon + label.
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type, this.compact = false});

  final ItemType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: type.tint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 12, color: type.accent),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              type.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: type.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/type_badge_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/widgets/type_badge.dart test/features/catalog/type_badge_test.dart
git commit -m "feat(catalog): add TypeBadge widget"
```

---

## Task 5: ItemPlaceholder widget

**Files:**
- Create: `lib/features/catalog/widgets/item_placeholder.dart`
- Test: `test/features/catalog/item_placeholder_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/item_placeholder_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/item_placeholder.dart';

Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 120, height: 120, child: child))));

void main() {
  testWidgets('shows uppercased first letter + type icon', (tester) async {
    await tester.pumpWidget(
        _wrap(const ItemPlaceholder(type: ItemType.product, name: 'silk saree')));
    expect(find.text('S'), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });

  testWidgets('falls back to ? for an empty name', (tester) async {
    await tester.pumpWidget(
        _wrap(const ItemPlaceholder(type: ItemType.other, name: '   ')));
    expect(find.text('?'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/item_placeholder_test.dart`
Expected: FAIL — `item_placeholder.dart` does not exist.

- [ ] **Step 3: Create the widget**

Create `lib/features/catalog/widgets/item_placeholder.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../data/item_type.dart';

/// Soft-letter placeholder for an imageless item: pale type-tint gradient, the
/// item's first letter in the accent color, and the type icon in the corner.
class ItemPlaceholder extends StatelessWidget {
  const ItemPlaceholder({
    super.key,
    required this.type,
    required this.name,
    this.letterSize = 40,
  });

  final ItemType type;
  final String name;
  final double letterSize;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: type.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: letterSize,
                fontWeight: FontWeight.w800,
                color: type.accent,
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Icon(type.icon, size: 15, color: type.accent.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/item_placeholder_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/widgets/item_placeholder.dart test/features/catalog/item_placeholder_test.dart
git commit -m "feat(catalog): add ItemPlaceholder widget"
```

---

## Task 6: Make ProductImage type-aware

**Files:**
- Modify: `lib/features/catalog/widgets/product_image.dart`
- Test: `test/features/catalog/product_image_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/product_image_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';

Widget _wrap(Widget child) => ProviderScope(
    child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 120, height: 120, child: child)))));

void main() {
  testWidgets('no path + type renders the type placeholder', (tester) async {
    await tester.pumpWidget(_wrap(
        const ProductImage(path: null, type: ItemType.service, name: 'Haircut')));
    expect(find.text('H'), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
  });

  testWidgets('no path + no type keeps the neutral placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const ProductImage(path: null)));
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/product_image_test.dart`
Expected: FAIL — `ProductImage` has no `type`/`name` parameters.

- [ ] **Step 3: Add type-aware placeholder to `ProductImage`**

In `lib/features/catalog/widgets/product_image.dart`:

Add the import:

```dart
import '../data/item_type.dart';
import 'item_placeholder.dart';
```

Add two fields + constructor params. Change the constructor to:

```dart
  const ProductImage({
    super.key,
    this.path,
    this.iconSize = 34,
    this.cacheWidth,
    this.type,
    this.name,
  });

  final String? path;
  final double iconSize;
  final int? cacheWidth;
  final ItemType? type;
  final String? name;
```

Replace `_placeholder()` with:

```dart
  Widget _placeholder() {
    final t = type;
    if (t != null) {
      return ItemPlaceholder(type: t, name: name ?? '', letterSize: iconSize + 6);
    }
    return Container(
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: Icon(
        Icons.photo_outlined,
        color: AppColors.textSecondary,
        size: iconSize,
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/product_image_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/widgets/product_image.dart test/features/catalog/product_image_test.dart
git commit -m "feat(catalog): make ProductImage placeholder type-aware"
```

---

## Task 7: ProductTile — badge + type-aware placeholder + product-only stock

**Files:**
- Modify: `lib/features/catalog/widgets/product_tile.dart`
- Test: `test/features/catalog/product_tile_test.dart` (modify)

- [ ] **Step 1: Update the placeholder test + add badge tests**

In `test/features/catalog/product_tile_test.dart`:

Add imports:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
```

Replace the existing `'shows placeholder when the product has no photo'` test body's
assertion — it currently expects `Icons.photo_outlined`, but tiles are now type-aware:

```dart
  testWidgets('imageless product shows the type placeholder', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799),
      onTap: () {},
    )));
    expect(find.text('C'), findsOneWidget); // first-letter placeholder
    expect(find.byIcon(Icons.photo_outlined), findsNothing);
  });

  testWidgets('shows the type badge', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Haircut', price: 300, type: 'service'),
      onTap: () {},
    )));
    expect(find.text('Service'), findsOneWidget);
  });

  testWidgets('non-product type hides stock text', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'E-book', price: 199, type: 'digital', qtyOnHand: 0),
      onTap: () {},
    )));
    expect(find.text('Out of stock'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/catalog/product_tile_test.dart`
Expected: FAIL — no badge; imageless tile still shows the neutral icon; stock shows for all.

- [ ] **Step 3: Update `ProductTile`**

In `lib/features/catalog/widgets/product_tile.dart`:

Add imports:

```dart
import 'item_placeholder.dart';
import 'type_badge.dart';
```

Pass `type` + `name` to `ProductImage` and add the badge overlay. Replace the
image `Stack` (the `Expanded(child: Stack(...))`) with:

```dart
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    path: product.coverImage,
                    cacheWidth: 600,
                    type: product.itemType,
                    name: product.name,
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: TypeBadge(type: product.itemType, compact: true),
                  ),
                  if (product.type == 'product' && product.isUnique)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: StatusPill(status: product.pieceStatus),
                    ),
                ],
              ),
            ),
```

Guard the stock text so it only shows for real products. Change the
`if (!product.isUnique)` condition in the price row to:

```dart
                      if (product.type == 'product' && !product.isUnique)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/catalog/product_tile_test.dart`
Expected: PASS (all tests, including the original unique/stock ones).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/widgets/product_tile.dart test/features/catalog/product_tile_test.dart
git commit -m "feat(catalog): show type badge + type placeholder on ProductTile"
```

---

## Task 8: Catalog filtering — pure helpers + filter bar

**Files:**
- Create: `lib/features/catalog/controller/catalog_filter.dart`
- Modify: `lib/features/catalog/presentation/catalog_screen.dart`
- Test: `test/features/catalog/catalog_filter_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/catalog_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/controller/catalog_filter.dart';
import 'package:orderly_app/features/catalog/data/product.dart';

void main() {
  final products = [
    Product(name: 'Saree', type: 'product', category: 'Sarees'),
    Product(name: 'Haircut', type: 'service', category: 'Salon'),
    Product(name: 'Facial', type: 'service', category: 'Salon'),
    Product(name: 'E-book', type: 'digital'),
  ];

  test('filterProducts by type', () {
    final r = filterProducts(products, type: 'service');
    expect(r.map((p) => p.name), ['Haircut', 'Facial']);
  });

  test('filterProducts by category', () {
    final r = filterProducts(products, category: 'Sarees');
    expect(r.map((p) => p.name), ['Saree']);
  });

  test('filterProducts with no filters returns all', () {
    expect(filterProducts(products).length, 4);
  });

  test('distinctCategories are sorted + de-duped, blanks dropped', () {
    expect(distinctCategories(products), ['Salon', 'Sarees']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/catalog_filter_test.dart`
Expected: FAIL — `catalog_filter.dart` does not exist.

- [ ] **Step 3: Create the filter helpers + providers**

Create `lib/features/catalog/controller/catalog_filter.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/product.dart';

/// Active catalog type filter (`null` = All).
final catalogTypeFilterProvider = StateProvider<String?>((_) => null);

/// Active catalog category filter (`null` = All).
final catalogCategoryFilterProvider = StateProvider<String?>((_) => null);

List<Product> filterProducts(List<Product> all, {String? type, String? category}) {
  return all.where((p) {
    if (type != null && p.type != type) return false;
    if (category != null && (p.category ?? '').trim() != category) return false;
    return true;
  }).toList();
}

List<String> distinctCategories(List<Product> all) {
  final set = <String>{};
  for (final p in all) {
    final c = p.category?.trim();
    if (c != null && c.isNotEmpty) set.add(c);
  }
  final list = set.toList()..sort();
  return list;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/catalog_filter_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Wire the filter bar into `catalog_screen.dart`**

In `lib/features/catalog/presentation/catalog_screen.dart`:

Add imports:

```dart
import '../controller/catalog_filter.dart';
import '../data/item_type.dart';
```

In `build`, after reading `productsAsync`, read the filters:

```dart
    final typeFilter = ref.watch(catalogTypeFilterProvider);
    final categoryFilter = ref.watch(catalogCategoryFilterProvider);
```

In the `data:` branch, filter before deciding empty vs grid:

```dart
              data: (products) {
                final categories = distinctCategories(products);
                final visible = filterProducts(products,
                    type: typeFilter, category: categoryFilter);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterBar(categories: categories),
                    Expanded(
                      child: products.isEmpty
                          ? CatalogEmptyState(onAdd: () => _openForm(context))
                          : _grid(context, ref, visible),
                    ),
                  ],
                );
              },
```

Add the `_FilterBar` widget at the bottom of the file:

```dart
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.categories});
  final List<String> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(catalogTypeFilterProvider);
    final category = ref.watch(catalogCategoryFilterProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _chip(
            label: 'All',
            selected: type == null,
            onTap: () =>
                ref.read(catalogTypeFilterProvider.notifier).state = null,
          ),
          for (final t in ItemType.values)
            _chip(
              label: t.label,
              selected: type == t.id,
              onTap: () =>
                  ref.read(catalogTypeFilterProvider.notifier).state = t.id,
            ),
          if (categories.isNotEmpty) const SizedBox(width: AppSpacing.md),
          for (final c in categories)
            _chip(
              label: c,
              selected: category == c,
              onTap: () => ref.read(catalogCategoryFilterProvider.notifier).state =
                  category == c ? null : c,
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
```

Make `CatalogScreen` filtering resilient: `_grid` already accepts a `List<Product>` — it
now receives the filtered `visible` list, no signature change needed.

- [ ] **Step 6: Run the analyzer + catalog tests**

Run: `flutter analyze lib/features/catalog`
Expected: no errors.
Run: `flutter test test/features/catalog/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/catalog/controller/catalog_filter.dart lib/features/catalog/presentation/catalog_screen.dart test/features/catalog/catalog_filter_test.dart
git commit -m "feat(catalog): filter catalog by item type + category"
```

---

## Task 9: Product form — type selector + conditional fields

**Files:**
- Modify: `lib/features/catalog/presentation/product_form_screen.dart`
- Test: `test/features/catalog/product_form_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/product_form_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/presentation/product_form_screen.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: child));

void main() {
  testWidgets('shows SKU + category for product type', (tester) async {
    await tester.pumpWidget(_wrap(const ProductFormScreen()));
    await tester.pumpAndSettle();
    expect(find.text('SKU'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Duration'), findsNothing);
  });

  testWidgets('switching to Service swaps to duration', (tester) async {
    await tester.pumpWidget(_wrap(const ProductFormScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service'));
    await tester.pumpAndSettle();
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('SKU'), findsNothing);
    expect(find.text('One-of-a-kind piece'), findsNothing);
  });

  testWidgets('editing an existing service preselects its type', (tester) async {
    await tester.pumpWidget(_wrap(ProductFormScreen(
        existing: Product(name: 'Facial', price: 500, type: 'service', duration: '60 min'))));
    await tester.pumpAndSettle();
    expect(find.text('Duration'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/product_form_screen_test.dart`
Expected: FAIL — no type selector; SKU/category/duration fields absent.

- [ ] **Step 3: Add type state + controllers**

In `lib/features/catalog/presentation/product_form_screen.dart`:

Add imports:

```dart
import '../data/item_type.dart';
```

Add fields to `_ProductFormScreenState` (near the other controllers):

```dart
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _duration;
  late final TextEditingController _deliveryMethod;
  late final TextEditingController _gstRate;
  late String _type;
```

In `initState`, after the existing initializers:

```dart
    _sku = TextEditingController(text: p?.sku ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _duration = TextEditingController(text: p?.duration ?? '');
    _deliveryMethod = TextEditingController(text: p?.deliveryMethod ?? '');
    _gstRate = TextEditingController(
        text: p?.gstRate == null ? '' : p!.gstRate!.toStringAsFixed(0));
    _type = p?.type ?? 'product';
```

In `dispose`, extend the loop list:

```dart
    for (final c in [
      _name, _price, _description, _qty,
      _sku, _category, _duration, _deliveryMethod, _gstRate,
    ]) {
      c.dispose();
    }
```

- [ ] **Step 4: Render the type selector + conditional fields**

In `build`, immediately after `_photoStrip()` and its `SizedBox`, insert the type
selector:

```dart
            _TypeSelector(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: AppSpacing.lg),
```

Keep the existing Name + Price + Description fields (shared by all types). Then
**replace** the block from the `SwitchListTile` (`One-of-a-kind piece`) through the
`if (!_isUnique) ...[ ... ]` qty section with type-conditional fields:

```dart
            if (_type == 'product') ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _sku,
                decoration: _decoration('SKU'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Category'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _gstRate,
                keyboardType: TextInputType.number,
                decoration: _decoration('Tax % (optional)'),
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile(
                value: _isUnique,
                onChanged: (v) => setState(() => _isUnique = v),
                activeTrackColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                title: const Text('One-of-a-kind piece',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'Single item that can be booked and sold once.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              if (!_isUnique) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: _decoration('Quantity in stock'),
                  validator: (v) {
                    if (_isUnique) return null;
                    final parsed = int.tryParse((v ?? '').trim());
                    if (parsed == null) return 'Enter a whole number';
                    if (parsed < 0) return 'Quantity cannot be negative';
                    return null;
                  },
                ),
              ],
            ] else if (_type == 'service') ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _duration,
                decoration: _decoration('Duration'),
              ),
            ] else if (_type == 'digital') ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _deliveryMethod,
                decoration: _decoration('Download / delivery method'),
              ),
            ],
```

- [ ] **Step 5: Persist the type-specific fields in `_save`**

In `_save`, replace the `qty` line + the two `controller.updateProduct` /
`controller.addProduct` calls so non-product types clear stock and each branch writes
its columns:

```dart
      final qty = (_type == 'product' && !_isUnique) ? int.parse(_qty.text.trim()) : 0;
      final isUnique = _type == 'product' && _isUnique;
      final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();
      final category = _category.text.trim().isEmpty ? null : _category.text.trim();
      final duration = _duration.text.trim().isEmpty ? null : _duration.text.trim();
      final delivery =
          _deliveryMethod.text.trim().isEmpty ? null : _deliveryMethod.text.trim();
      final gst = double.tryParse(_gstRate.text.trim());

      if (_isEdit) {
        await controller.updateProduct(widget.existing!.id!, {
          'name': name,
          'price': price,
          'description': description,
          'type': _type,
          'is_unique': isUnique,
          'qty_on_hand': qty,
          'sku': _type == 'product' ? sku : null,
          'category': _type == 'product' ? category : null,
          'gst_rate': _type == 'product' ? gst : null,
          'duration': _type == 'service' ? duration : null,
          'delivery_method': _type == 'digital' ? delivery : null,
          'images': images,
        });
      } else {
        await controller.addProduct(Product(
          name: name,
          price: price,
          description: description,
          type: _type,
          isUnique: isUnique,
          qtyOnHand: qty,
          sku: _type == 'product' ? sku : null,
          category: _type == 'product' ? category : null,
          gstRate: _type == 'product' ? gst : null,
          duration: _type == 'service' ? duration : null,
          deliveryMethod: _type == 'digital' ? delivery : null,
          images: images,
        ));
        ref.read(eventServiceProvider).track('catalog_item_added');
      }
```

Confirm the `Product` constructor accepts `sku` (it already does). Update the AppBar
title so it isn't piece-specific for non-products — change it to:

```dart
        title: Text(_isEdit ? 'Edit item' : 'Add item'),
```

- [ ] **Step 6: Add the `_TypeSelector` widget**

At the bottom of the file:

```dart
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final t in ItemType.values)
          ChoiceChip(
            avatar: Icon(t.icon,
                size: 16,
                color: value == t.id ? t.accent : AppColors.textSecondary),
            label: Text(t.label),
            selected: value == t.id,
            selectedColor: t.tint,
            onSelected: (_) => onChanged(t.id),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/features/catalog/product_form_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/features/catalog/presentation/product_form_screen.dart test/features/catalog/product_form_screen_test.dart
git commit -m "feat(catalog): type selector + per-type fields in product form"
```

---

## Task 10: OrderItem + CreateOrderItem carry type + image

**Files:**
- Modify: `lib/features/orders/data/order.dart`
- Modify: `lib/features/orders/data/create_order_draft.dart`
- Test: `test/features/orders/order_item_type_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/order_item_type_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/order.dart';

void main() {
  test('OrderItem reads item_type + defaults to product', () {
    final withType = OrderItem.fromMap(
        {'name': 'Haircut', 'qty': 1, 'item_type': 'service'});
    expect(withType.type, 'service');
    expect(withType.itemType, ItemType.service);
    expect(OrderItem.fromMap({'name': 'X'}).type, 'product');
  });

  test('CreateOrderItem keeps type + imageUrl across copyWith', () {
    const item = CreateOrderItem(
        name: 'E-book', unitPrice: 199, type: 'digital', imageUrl: 'u/x.jpg');
    final bumped = item.copyWith(qty: 3);
    expect(bumped.type, 'digital');
    expect(bumped.imageUrl, 'u/x.jpg');
    expect(bumped.lineTotal, 597);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/order_item_type_test.dart`
Expected: FAIL — `OrderItem.type`/`CreateOrderItem.type`/`imageUrl` absent.

- [ ] **Step 3: Add `type` to `OrderItem`**

In `lib/features/orders/data/order.dart`:

Add import:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
```

Add constructor param `this.type = 'product',`, field `final String type;`, getter
`ItemType get itemType => ItemType.fromId(type);`, and in `fromMap` add:

```dart
      type: (map['item_type'] ?? 'product').toString(),
```

- [ ] **Step 4: Add `type` + `imageUrl` to `CreateOrderItem`**

In `lib/features/orders/data/create_order_draft.dart`, replace the `CreateOrderItem`
class with:

```dart
class CreateOrderItem {
  const CreateOrderItem({
    required this.name,
    this.qty = 1,
    this.unitPrice = 0,
    this.productId,
    this.type = 'product',
    this.imageUrl,
  });

  final String name;
  final int qty;
  final double unitPrice;
  final String? productId;
  final String type;
  final String? imageUrl;

  double get lineTotal => qty * unitPrice;

  CreateOrderItem copyWith({String? name, int? qty, double? unitPrice}) =>
      CreateOrderItem(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        productId: productId,
        type: type,
        imageUrl: imageUrl,
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/orders/order_item_type_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/orders/data/order.dart lib/features/orders/data/create_order_draft.dart test/features/orders/order_item_type_test.dart
git commit -m "feat(orders): carry item type + image on order items"
```

---

## Task 11: create_order_provider — qty stepper + merge-by-product

**Files:**
- Modify: `lib/features/orders/controller/create_order_provider.dart`
- Test: `test/features/orders/create_order_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/create_order_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/create_order_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

class _FakeOrdersService extends OrdersService {}

void main() {
  CreateOrderNotifier make() =>
      CreateOrderNotifier(_FakeOrdersService(), 'cust-1', 'Asha');

  test('re-adding the same product merges quantity', () {
    final n = make();
    n.addItem(const CreateOrderItem(
        name: 'Saree', unitPrice: 2499, productId: 'p1', type: 'product'));
    n.addItem(const CreateOrderItem(
        name: 'Saree', unitPrice: 2499, productId: 'p1', type: 'product'));
    expect(n.state.draft.items.length, 1);
    expect(n.state.draft.items.first.qty, 2);
  });

  test('custom items (no productId) never merge', () {
    final n = make();
    n.addItem(const CreateOrderItem(name: 'Charge', unitPrice: 100));
    n.addItem(const CreateOrderItem(name: 'Charge', unitPrice: 100));
    expect(n.state.draft.items.length, 2);
  });

  test('setQty updates a line; zero removes it', () {
    final n = make();
    n.addItem(const CreateOrderItem(name: 'A', unitPrice: 50, productId: 'p1'));
    n.setQty(0, 4);
    expect(n.state.draft.items.first.qty, 4);
    n.setQty(0, 0);
    expect(n.state.draft.items, isEmpty);
  });
}
```

> `OrdersService` has an implicit no-arg constructor and resolves its Supabase client
> lazily through a getter (`SupabaseClient get _client => Supabase.instance.client`), so
> `_FakeOrdersService` constructs fine without a live client — these provider tests never
> call a network method.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/create_order_provider_test.dart`
Expected: FAIL — `setQty` missing; `addItem` appends instead of merging.

- [ ] **Step 3: Update `addItem` + add `setQty`**

In `lib/features/orders/controller/create_order_provider.dart`, replace `addItem`
with a merging version and add `setQty`:

```dart
  void addItem(CreateOrderItem item) {
    final items = List<CreateOrderItem>.of(state.draft.items);
    if (item.productId != null) {
      final i = items.indexWhere((e) => e.productId == item.productId);
      if (i != -1) {
        items[i] = items[i].copyWith(qty: items[i].qty + item.qty);
        state = state.copyWith(draft: state.draft.copyWith(items: items));
        return;
      }
    }
    items.add(item);
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }

  void setQty(int index, int qty) {
    final items = List<CreateOrderItem>.of(state.draft.items);
    if (index < 0 || index >= items.length) return;
    if (qty <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(qty: qty);
    }
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/orders/create_order_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/controller/create_order_provider.dart test/features/orders/create_order_provider_test.dart
git commit -m "feat(orders): merge-by-product + qty stepper in order draft"
```

---

## Task 12: orders_service — send item_type + image_url

**Files:**
- Modify: `lib/features/orders/data/orders_service.dart:55-64` (the `payload` map)
- Test: `test/features/orders/order_payload_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/order_payload_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

void main() {
  test('buildItemsPayload includes item_type + image_url snapshot', () {
    final payload = buildItemsPayload([
      const CreateOrderItem(
          name: 'Saree',
          unitPrice: 2499,
          qty: 2,
          productId: 'p1',
          type: 'product',
          imageUrl: 'u/1.jpg'),
      const CreateOrderItem(name: 'Charge', unitPrice: 100), // custom
    ]);
    expect(payload[0]['item_type'], 'product');
    expect(payload[0]['image_url'], 'u/1.jpg');
    expect(payload[0]['product_id'], 'p1');
    expect(payload[1].containsKey('product_id'), isFalse);
    expect(payload[1].containsKey('image_url'), isFalse);
    expect(payload[1]['item_type'], 'product');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/order_payload_test.dart`
Expected: FAIL — `buildItemsPayload` does not exist.

- [ ] **Step 3: Extract + extend the payload builder**

In `lib/features/orders/data/orders_service.dart`, add a top-level function (above the
class) and use it inside `createOrder`:

```dart
/// Serializes draft items into the jsonb `p_items` array the create-order RPC
/// consumes. `item_type` + `image_url` are snapshotted for badge display.
List<Map<String, dynamic>> buildItemsPayload(List<CreateOrderItem> items) {
  return items
      .map((i) => {
            'name': i.name,
            'qty': i.qty,
            'unit_price': i.unitPrice,
            'item_type': i.type,
            if (i.productId != null) 'product_id': i.productId,
            if (i.imageUrl != null) 'image_url': i.imageUrl,
          })
      .toList();
}
```

Replace the inline `final payload = items.map(...)` in `createOrder` with:

```dart
    final payload = buildItemsPayload(items);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/orders/order_payload_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/data/orders_service.dart test/features/orders/order_payload_test.dart
git commit -m "feat(orders): snapshot item_type + image_url into create-order RPC"
```

---

## Task 13: OrderItemRowCard widget

**Files:**
- Create: `lib/features/orders/widgets/order_item_row_card.dart`
- Test: `test/features/orders/order_item_row_card_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/order_item_row_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/orders/widgets/order_item_row_card.dart';

Widget _wrap(Widget child) => ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('editable card shows stepper + line total + badge', (tester) async {
    var qty = 2;
    await tester.pumpWidget(_wrap(OrderItemRowCard(
      name: 'Silk Saree',
      type: ItemType.product,
      imagePath: null,
      unitPrice: 2499,
      qty: qty,
      onQtyChanged: (v) => qty = v,
      onRemove: () {},
    )));
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('₹4,998'), findsOneWidget); // 2 x 2499
    await tester.tap(find.byIcon(Icons.add));
    expect(qty, 3);
  });

  testWidgets('read-only card hides stepper + remove', (tester) async {
    await tester.pumpWidget(_wrap(const OrderItemRowCard(
      name: 'Haircut',
      type: ItemType.service,
      imagePath: null,
      unitPrice: 300,
      qty: 1,
    )));
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('₹300'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/order_item_row_card_test.dart`
Expected: FAIL — `order_item_row_card.dart` does not exist.

- [ ] **Step 3: Create the widget**

Create `lib/features/orders/widgets/order_item_row_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

/// One selected item in the order builder (editable) or order detail (read-only).
/// Editable when both [onQtyChanged] and [onRemove] are provided.
class OrderItemRowCard extends StatelessWidget {
  const OrderItemRowCard({
    super.key,
    required this.name,
    required this.type,
    required this.imagePath,
    required this.unitPrice,
    required this.qty,
    this.onQtyChanged,
    this.onRemove,
  });

  final String name;
  final ItemType type;
  final String? imagePath;
  final double unitPrice;
  final int qty;
  final ValueChanged<int>? onQtyChanged;
  final VoidCallback? onRemove;

  bool get _editable => onQtyChanged != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ProductImage(
                path: imagePath,
                type: type,
                name: name,
                iconSize: 18,
                cacheWidth: 160,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                TypeBadge(type: type, compact: false),
                const SizedBox(height: 2),
                Text('${Money.inr(unitPrice)} each',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_editable)
                _Stepper(
                  qty: qty,
                  onChanged: onQtyChanged!,
                )
              else
                Text('× $qty',
                    style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(Money.inr(unitPrice * qty),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (_editable && onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: AppColors.textSecondary,
              onPressed: onRemove,
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.onChanged});
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove, () => onChanged(qty - 1)),
          SizedBox(
            width: 24,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          _btn(Icons.add, () => onChanged(qty + 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/orders/order_item_row_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/widgets/order_item_row_card.dart test/features/orders/order_item_row_card_test.dart
git commit -m "feat(orders): add OrderItemRowCard (editable + read-only)"
```

---

## Task 14: Order builder — picker sheet + row cards

**Files:**
- Create: `lib/features/orders/widgets/item_picker_sheet.dart`
- Modify: `lib/features/orders/presentation/create_order_screen.dart`
- Test: `test/features/orders/item_picker_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/item_picker_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/orders/widgets/item_picker_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final products = [
    Product(name: 'Silk Saree', price: 2499, type: 'product'),
    Product(name: 'Haircut', price: 300, type: 'service'),
  ];

  testWidgets('filters the grid by search text', (tester) async {
    await tester.pumpWidget(_wrap(ItemPickerSheet(
      products: products,
      onPick: (_) {},
      onCustom: () {},
    )));
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'hair');
    await tester.pump();
    expect(find.text('Silk Saree'), findsNothing);
    expect(find.text('Haircut'), findsOneWidget);
  });

  testWidgets('tapping a tile fires onPick', (tester) async {
    Product? picked;
    await tester.pumpWidget(_wrap(ItemPickerSheet(
      products: products,
      onPick: (p) => picked = p,
      onCustom: () {},
    )));
    await tester.tap(find.text('Silk Saree'));
    expect(picked?.name, 'Silk Saree');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/item_picker_sheet_test.dart`
Expected: FAIL — `item_picker_sheet.dart` does not exist.

- [ ] **Step 3: Create the picker sheet**

Create `lib/features/orders/widgets/item_picker_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/catalog/controller/catalog_filter.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

/// Bottom-sheet catalog picker for the order builder: search + type + category
/// filters over an image-tile grid, plus a custom-item escape hatch.
class ItemPickerSheet extends StatefulWidget {
  const ItemPickerSheet({
    super.key,
    required this.products,
    required this.onPick,
    required this.onCustom,
  });

  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onCustom;

  @override
  State<ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<ItemPickerSheet> {
  String _query = '';
  String? _type;
  String? _category;

  @override
  Widget build(BuildContext context) {
    final categories = distinctCategories(widget.products);
    var visible = filterProducts(widget.products, type: _type, category: _category);
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      visible = visible.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Add item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                TextButton.icon(
                  onPressed: widget.onCustom,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Custom item'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search items',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('All', _type == null, () => setState(() => _type = null)),
                  for (final t in ItemType.values)
                    _chip(t.label, _type == t.id,
                        () => setState(() => _type = t.id)),
                  if (categories.isNotEmpty) const SizedBox(width: AppSpacing.md),
                  for (final c in categories)
                    _chip(c, _category == c,
                        () => setState(() => _category = _category == c ? null : c)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text('No matching items',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) =>
                          _tile(context, visible[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _tile(BuildContext context, Product p) {
    return GestureDetector(
      onTap: () => widget.onPick(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ProductImage(
                    path: p.coverImage,
                    type: p.itemType,
                    name: p.name,
                    cacheWidth: 240,
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: TypeBadge(type: p.itemType, compact: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          Text(Money.inr(p.price),
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the picker test to verify it passes**

Run: `flutter test test/features/orders/item_picker_sheet_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the sheet + row cards into `create_order_screen.dart`**

In `lib/features/orders/presentation/create_order_screen.dart`:

Add imports:

```dart
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/orders/widgets/item_picker_sheet.dart';
import 'package:orderly_app/features/orders/widgets/order_item_row_card.dart';
```

Replace the Items `_Section` `child:` (the `draft.items.isEmpty ? ... : Column(...)`
block) with row cards:

```dart
            child: draft.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('No items added yet.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < draft.items.length; i++)
                        OrderItemRowCard(
                          key: Key('item_row_$i'),
                          name: draft.items[i].name,
                          type: ItemType.fromId(draft.items[i].type),
                          imagePath: draft.items[i].imageUrl,
                          unitPrice: draft.items[i].unitPrice,
                          qty: draft.items[i].qty,
                          onQtyChanged: (v) => ref
                              .read(createOrderProvider(_key).notifier)
                              .setQty(i, v),
                          onRemove: () => ref
                              .read(createOrderProvider(_key).notifier)
                              .removeItem(i),
                        ),
                    ],
                  ),
```

Add the `ItemType` import too:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
```

Change the Items section `trailing` "Add Item" button to open the picker:

```dart
            trailing: TextButton.icon(
              onPressed: () => _openPicker(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Item'),
            ),
```

Replace the `_addItemDialog` method with a picker launcher + a kept custom-item dialog:

```dart
  void _openPicker(BuildContext context) {
    final productsAsync = ref.read(productsControllerProvider);
    final products = productsAsync.valueOrNull ?? const <Product>[];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ItemPickerSheet(
          products: products,
          onPick: (p) {
            ref.read(createOrderProvider(_key).notifier).addItem(
                  CreateOrderItem(
                    name: p.name,
                    unitPrice: p.price,
                    productId: p.id,
                    type: p.type,
                    imageUrl: p.coverImage,
                  ),
                );
            Navigator.pop(ctx);
          },
          onCustom: () {
            Navigator.pop(ctx);
            _addCustomItemDialog(context);
          },
        ),
      ),
    );
  }

  void _addCustomItemDialog(BuildContext context) {
    final nameCtl = TextEditingController();
    final priceCtl = TextEditingController();
    final qtyCtl = TextEditingController(text: '1');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtl,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: priceCtl,
                    decoration: const InputDecoration(labelText: 'Unit price ₹'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final qty = int.tryParse(qtyCtl.text) ?? 1;
              final price = double.tryParse(priceCtl.text) ?? 0;
              ref.read(createOrderProvider(_key).notifier).addItem(
                    CreateOrderItem(
                        name: name, qty: qty, unitPrice: price, type: 'other'),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
```

Delete the now-unused `_ItemRow` class at the bottom of the file (replaced by
`OrderItemRowCard`).

- [ ] **Step 6: Run the analyzer + order tests**

Run: `flutter analyze lib/features/orders`
Expected: no errors (no references to the deleted `_ItemRow`).
Run: `flutter test test/features/orders/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/orders/widgets/item_picker_sheet.dart lib/features/orders/presentation/create_order_screen.dart test/features/orders/item_picker_sheet_test.dart
git commit -m "feat(orders): image-tile item picker + row cards in order builder"
```

---

## Task 15: Order detail — read-only row cards

**Files:**
- Modify: `lib/features/orders/presentation/order_detail_screen.dart:274-312`
- Test: `test/features/orders/order_detail_items_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/orders/order_detail_items_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: child));

void main() {
  testWidgets('renders items as row cards with type badges', (tester) async {
    final order = Order(
      id: 'o1',
      orderNumber: 7,
      grandTotal: 4998,
      items: const [
        OrderItem(name: 'Silk Saree', unitPrice: 2499, qty: 2, type: 'product'),
      ],
    );
    await tester.pumpWidget(_wrap(OrderDetailScreen(order: order)));
    await tester.pumpAndSettle();
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Product'), findsWidgets); // badge label
    expect(find.byIcon(Icons.close), findsNothing); // read-only, no remove
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/order_detail_items_test.dart`
Expected: FAIL — items still render as `qty × name` text (no `TypeBadge`).

- [ ] **Step 3: Swap the Items text rows for read-only row cards**

In `lib/features/orders/presentation/order_detail_screen.dart`:

Add imports:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
import '../widgets/order_item_row_card.dart';
```

In the Items `AppCard`, replace the `for (final it in order.items) Padding(... Row ...)`
block with:

```dart
                for (final it in order.items)
                  OrderItemRowCard(
                    name: it.name,
                    type: it.itemType,
                    imagePath: it.imageUrl,
                    unitPrice: it.unitPrice,
                    qty: it.qty,
                  ),
```

Leave the `Divider`, Total row, and status pill below it unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/orders/order_detail_items_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/presentation/order_detail_screen.dart test/features/orders/order_detail_items_test.dart
git commit -m "feat(orders): render order-detail items as type row cards"
```

---

## Task 16: Invoice — type label per line

**Files:**
- Modify: `lib/features/invoices/data/invoice_data.dart`
- Modify: `lib/features/invoices/pdf/classic.dart:58`, `lib/features/invoices/pdf/boutique.dart:58`, `lib/features/invoices/pdf/minimal.dart:40`
- Test: `test/features/invoices/invoice_data_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/features/invoices/invoice_data_test.dart` (inside its `main`):

```dart
  test('InvoiceLine.displayName appends label for non-product types', () {
    const product = InvoiceLine(
        name: 'Saree', qty: 1, unitPrice: 100, gstRate: 0, lineTotal: 100,
        type: 'product');
    const service = InvoiceLine(
        name: 'Haircut', qty: 1, unitPrice: 300, gstRate: 0, lineTotal: 300,
        type: 'service');
    expect(product.displayName, 'Saree');
    expect(service.displayName, 'Haircut · Service');
  });
```

Ensure the test file imports the invoice data lib (add if missing):

```dart
import 'package:orderly_app/features/invoices/data/invoice_data.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/invoices/invoice_data_test.dart`
Expected: FAIL — `InvoiceLine` has no `type`/`displayName`.

- [ ] **Step 3: Add `type` + `displayName` to `InvoiceLine`**

In `lib/features/invoices/data/invoice_data.dart`:

Add the import:

```dart
import 'package:orderly_app/features/catalog/data/item_type.dart';
```

Replace the `InvoiceLine` class with:

```dart
class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.gstRate,
    required this.lineTotal,
    this.type = 'product',
  });

  final String name;
  final int qty;
  final double unitPrice;
  final double gstRate;
  final double lineTotal;
  final String type;

  /// Name with a type suffix for non-product lines (products need no label).
  String get displayName =>
      type == 'product' ? name : '$name · ${ItemType.fromId(type).label}';
}
```

In `InvoiceData.fromOrder`, pass the type when building each line — change the
`lines.add(InvoiceLine(...))` to include:

```dart
        type: it.type,
```

- [ ] **Step 4: Use `displayName` in the three PDF templates**

- `lib/features/invoices/pdf/classic.dart:58` — change `l.name,` to `l.displayName,`
- `lib/features/invoices/pdf/boutique.dart:58` — change `pw.Text('${l.name}  x${l.qty}')`
  to `pw.Text('${l.displayName}  x${l.qty}')`
- `lib/features/invoices/pdf/minimal.dart:40` — change
  `pw.Text('${l.name}   ${l.qty} x ${pdfMoney(l.unitPrice)}')` to
  `pw.Text('${l.displayName}   ${l.qty} x ${pdfMoney(l.unitPrice)}')`

- [ ] **Step 5: Run the invoice tests to verify they pass**

Run: `flutter test test/features/invoices/`
Expected: PASS (existing invoice tests + the new `displayName` test).

- [ ] **Step 6: Commit**

```bash
git add lib/features/invoices/data/invoice_data.dart lib/features/invoices/pdf/classic.dart lib/features/invoices/pdf/boutique.dart lib/features/invoices/pdf/minimal.dart test/features/invoices/invoice_data_test.dart
git commit -m "feat(invoices): label non-product item types on invoice lines"
```

---

## Task 17: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Analyzer clean**

Run: `flutter analyze`
Expected: `No issues found!` Fix any warning introduced by the changes (unused imports,
the deleted `_ItemRow`, etc.).

- [ ] **Step 2: Full test suite green**

Run: `flutter test`
Expected: all tests pass. Pay attention to any pre-existing catalog/order tests that
touched item rows or placeholders.

- [ ] **Step 3: Manual smoke (device/emulator)**

Run the app against a DB with migration `0030` applied and confirm:
- Add one item of each type — catalog shows the badge + (for imageless) the soft-letter
  placeholder; stock text appears only on products.
- Filter the catalog by a type chip and a category chip.
- Build an order via the picker: search, filter, tap a tile, adjust the stepper (subtotal
  updates), re-add the same product (qty merges), add a custom item.
- Open the order → items render as row cards with badges.
- Share the invoice → non-product lines show the ` · Type` suffix.

- [ ] **Step 4: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "chore(catalog): verification fixes for item types rollout"
```

---

## Self-review notes (for the implementer)

- **Spec coverage:** types + accents (Task 1), schema + RPC (Task 2), per-type product
  fields (Tasks 3, 9), image catalog cards + placeholder (Tasks 5–7), catalog type/category
  filter (Task 8), image order builder + picker with search/type/category (Tasks 13, 14),
  order-detail cards (Task 15), invoice type label (Task 16), empty-image placeholder
  (Tasks 5, 6). Recently Used / Frequently Ordered are intentionally **out of scope**.
- **Future-ready:** adding a new type = one `ItemType` entry + its `AppColors` tokens +
  the DB check constraint; every badge/placeholder/filter/picker reads from the registry.
- **`OrdersService` test constructibility (Task 11):** the fake builds without a live
  client (lazy getter, implicit no-arg constructor); provider tests never hit the network.
