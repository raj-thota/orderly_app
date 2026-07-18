# Catalog & Orders — Item Types + Visual Redesign

**Date:** 2026-07-18
**Branch target:** `mvp_release`
**Status:** Approved design → implementation planning

## Goal

Make the Catalog and Orders experience visual and flexible. Introduce **item types** so
Closr supports products, services, digital products, and misc charges — each with its own
icon and accent. Replace text-row catalog/order UI with image cards inspired by
Shopify / Apple Store / Stripe, staying within the existing Closr design system
(indigo `#5B4FE9`, soft shadows, `AppColors`/`AppSpacing`/`AppRadius` tokens).

## Scope decisions (locked)

| Decision | Choice |
| --- | --- |
| Type depth | **Display + fields only.** Order lifecycle (`pending→packed→shipped→delivered` + courier) is unchanged for every type. Type is stamped onto `order_items` purely for badge display. |
| Add-Item picker | **Core picker**: image grid + search + type filter + category filter + custom-item escape hatch. **Recently Used / Frequently Ordered deferred.** |
| Category | **Free-text + autocomplete** from existing distinct values. No managed taxonomy table. |
| Type badge | **Soft tint** — light type-tint pill, accent-colored icon + label. |
| Empty placeholder | **Soft letter** — pale type-tint gradient + accent first letter + corner type icon. |
| Order-builder item | **Row card** — thumb, name, badge, unit price, qty stepper, line total, remove. Order detail + invoice reuse a read-only variant. |

## Type registry

Four supported types, designed so new types (subscription, membership, rental, bundle,
gift card) can be added by appending **one registry entry** — no widget changes.

| id | label | Material icon | accent | tint (badge bg) |
| --- | --- | --- | --- | --- |
| `product` | Product | `inventory_2` | `#5B4FE9` indigo | `#ECEBFD` |
| `service` | Service | `handyman` | `#0D9488` teal | `#E0F2F0` |
| `digital` | Digital Product | `devices` | `#7C3AED` violet | `#F1EBFE` |
| `other` | Other | `category` | `#64748B` slate | `#EEF1F5` |

Registry lives in `lib/features/catalog/data/item_type.dart`:

```dart
class ItemType {
  final String id;      // db value
  final String label;   // display
  final IconData icon;
  final Color accent;   // from AppColors token
  final Color tint;     // from AppColors token
  final (Color, Color) gradient; // soft placeholder gradient
  const ItemType(...);

  static const values = [product, service, digital, other];
  static ItemType fromId(String? id) => // match or fallback to `other`
}
```

Accent + tint colors are added as tokens to `AppColors` (no hardcoded `Color(0x..)` in
widgets — the registry references the tokens). Placeholder gradients are derived from the
tint pair.

## Data model

New migration `supabase/migrations/0030_item_types.sql`, fully idempotent
(`add column if not exists`, guarded checks). No new tables → inherits existing
`products` / `order_items` RLS.

**`products`** — add:
- `type text not null default 'product'` with `check (type in ('product','service','digital','other'))`
- `category text` (nullable, free-text)
- `duration text` (nullable — service, e.g. `"45 min"`)
- `delivery_method text` (nullable — digital, e.g. `"Email link"`, `"Download"`)

Existing `is_unique` / `qty_on_hand` / `piece_status` apply to `type = 'product'` only.
Non-product types are always available (no stock tracking).

**`order_items`** — add:
- `item_type text not null default 'product'` with the same check — a snapshot of the
  product's type at order time, for badge display on detail + invoice.

Backfill: existing rows adopt `'product'` via the column defaults.

**Index:** `create index if not exists idx_products_user_type on public.products(user_id, type);`
(supports the catalog type filter should it ever move server-side; catalog is currently
filtered client-side).

**RPC — `create_order_with_items`:** current v3 (`0020`) inserts `order_items`
`(user_id, order_id, product_id, name, image_url, unit_price, gst_rate, qty, line_total)`
from each `p_items` jsonb element. The migration replaces the function body (v4) to also
insert `item_type` from `v_item->>'item_type'` (default `'product'` when absent). The
parameter signature is unchanged (type rides inside `p_items`), so no `drop`/re-`grant`
is needed — `create or replace` only.

## Components & changes

### Models
- `Product` (`catalog/data/product.dart`): add `type`, `category`, `duration`,
  `deliveryMethod`; update `fromMap`/`toMap`/`copyWith`. Add
  `ItemType get itemType => ItemType.fromId(type)`.
- `OrderItem` (`orders/data/order.dart`): add `type` from `item_type`.
- `CreateOrderItem` (`orders/data/create_order_draft.dart`): add `type`, `imageUrl`;
  `copyWith` supports `qty`.

### Shared widgets (`catalog/widgets/`)
- `TypeBadge(ItemType type, {compact})` — soft-tint pill, reused in catalog tile, picker
  tile, order row, order detail row, invoice line.
- `ItemPlaceholder(ItemType type, String name)` — soft-letter gradient (pale tint,
  accent first letter, corner type icon). Wired into `ProductImage`: it gains optional
  `type` + `name` and renders `ItemPlaceholder` instead of the grey photo icon when no
  image resolves. Every existing `ProductImage` call site becomes type-aware.

### Catalog
- `ProductTile`: overlay `TypeBadge` top-left; show stock / piece-status **only** for
  `product`; imageless items use the type placeholder.
- `catalog_screen`: filter bar above the grid — a row of type chips (`All` + 4 types) and,
  when categories exist, a row of category chips. Filtering is client-side over the loaded
  product list (user-scoped, small). A `catalogFilterProvider` holds the active
  type/category; `distinctCategoriesProvider` derives chips from loaded products.

### Product form (`product_form_screen.dart`)
- Add a **type selector** (4 chips / segmented) at the top; defaults to `product` for new
  items, existing type on edit.
- Conditional fields by type:
  - **Product** — name, images, SKU, category, stock (unique switch / qty), price, tax
    (`gst_rate`), description. *(Exposes the currently-hidden SKU, category, tax fields.)*
  - **Service** — name, images (optional), duration, price, description.
  - **Digital** — name, images (optional), price, delivery method, description.
  - **Other** — name, images (optional), price, description.
- Images are optional for all types (placeholder covers none). Save writes `type` +
  relevant columns; irrelevant columns are set null.
- Copy is de-piece-ified where type ≠ product-unique (titles read "item" not "piece").

### Order builder (`create_order_screen.dart` + `create_order_provider.dart`)
- Replace `_addItemDialog` (plain text) with a **catalog picker** modal bottom sheet:
  search field + type filter chips + category filter chips + grid of image tiles
  (tap to add), plus a `＋ Custom item` action that opens the old name/qty/price mini-form
  (covers ad-hoc "Other" charges — items with no `productId`).
- Selected items render as **row cards** (`OrderItemRowCard`): thumbnail/placeholder,
  name, `TypeBadge`, unit price, qty stepper (`−`/`＋`), line total, remove `✕`.
- Provider: add `setQty(i, qty)` / `incQty` / `decQty`; `addItem` **merges by
  `productId`** (re-adding a product increments qty rather than duplicating). Custom items
  (null `productId`) never merge.
- `create_order_provider.submit` includes `item_type` + `image_url` in each `p_items` map.

### Order detail + invoice
- `order_detail_screen`: replace `qty × name` text rows with read-only `OrderItemRowCard`
  (no stepper / no remove) — thumbnail/placeholder, name, `TypeBadge`, qty, line total.
- Invoice (`invoices/`): add a small type label/icon per line where applicable. Exact
  render point verified against the invoice widget/PDF at implementation.

### Services / providers
- `products_service`: add new columns to select/insert/update.
- `orders_service`: `p_items` map gains `item_type` + `image_url` (sourced from the
  product at add time).

## Testing

- **Widgets:** `TypeBadge` shows correct label/icon/accent per type; `ItemPlaceholder`
  renders first letter + type icon; `ProductTile` shows badge always but stock only for
  `product`.
- **Form:** switching type shows/hides the correct field set; save writes the correct
  columns (irrelevant ones null).
- **Order builder:** picker → row card; stepper updates line total + subtotal; re-adding a
  product merges qty; custom-item path produces a null-`productId` row.
- **Models:** `Product` / `OrderItem` / `CreateOrderItem` `fromMap`↔`toMap` round-trip with
  new fields; `ItemType.fromId` falls back to `other` on unknown/null.
- **Migration:** idempotent re-run is a no-op; backfill leaves existing rows as `product`;
  RPC v4 inserts `item_type`.

## Non-goals (this pass)

- Per-type order fulfillment lifecycle (services/digital keep the physical flow for now).
- Recently Used / Frequently Ordered rails (need order-history aggregation).
- Managed category taxonomy (free-text only).
- Actually adding subscription / membership / rental / bundle / gift-card types — the
  registry supports them; none are added now.

## Verification

`flutter analyze` clean, `flutter test` green, migration applies idempotently against a
scratch DB before prod. Manual pass: create one item of each type, confirm badge +
placeholder in catalog, build an order via the picker with a stepper change + a custom
item, confirm detail + invoice render the type.
