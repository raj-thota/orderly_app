# Image-First Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stage 2 of the Closr spec — an image-first product catalog: photo capture/upload with compression to private storage, price, unique-piece vs stocked toggle, availability states (available/booked/sold, qty on hand), surfaced as a 4th "Catalog" tab.

**Architecture:** New `lib/features/catalog/` feature following the established layering: typed `Product` model (`fromMap`/`toMap`, no codegen), `ProductsService` wrapping the existing `products` table + private `product-images` bucket (both already migrated with RLS/policies — **no DB migration in this plan**), Riverpod `StateNotifier` controller that reloads after each mutation, and three screens (grid, form, detail). Images upload compressed under `<user_id>/...` paths and display via short-lived signed URLs cached in memory until near expiry.

**Tech Stack:** Flutter, Riverpod, Supabase Storage + Postgres, `image_picker` (new dep), `flutter_image_compress` (new dep), `flutter_test`.

**Not in this plan (per spec §11 staging):** "Create enquiry from product" (needs customers — stage 3), automatic booking on order (stage 4), Leads→Enquiries rename (stage 3), search/filters (YAGNI for v1 catalog).

---

## File structure

**Created**
- `lib/features/catalog/data/product.dart` — typed model + availability logic
- `lib/features/catalog/data/signed_url_cache.dart` — in-memory signed-URL cache with expiry
- `lib/features/catalog/data/products_service.dart` — Supabase CRUD + compress/upload + signed URLs
- `lib/features/catalog/controller/products_provider.dart` — Riverpod controller + image-URL family provider
- `lib/features/catalog/widgets/product_image.dart` — signed-URL image with placeholder (shared by tile + detail)
- `lib/features/catalog/widgets/product_tile.dart` — grid tile (image hero, pill, price, stock)
- `lib/features/catalog/widgets/catalog_empty_state.dart` — empty state with CTA
- `lib/features/catalog/presentation/catalog_screen.dart` — 2-column grid tab
- `lib/features/catalog/presentation/product_form_screen.dart` — add/edit with photo picking
- `lib/features/catalog/presentation/product_detail_screen.dart` — gallery, status control, qty, archive
- `test/features/catalog/product_test.dart`
- `test/features/catalog/signed_url_cache_test.dart`
- `test/features/catalog/product_tile_test.dart`

**Modified**
- `pubspec.yaml` — add `image_picker`, `flutter_image_compress`
- `ios/Runner/Info.plist` — camera + photo-library usage strings
- `lib/main.dart` — 4th tab, context-aware FAB
- `lib/shared/widgets/app_bottom_nav.dart` — Catalog nav item

---

## Task 1: Dependencies + platform permission strings

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml`, add to the `dependencies:` block (after `flutter_dotenv: ^5.1.0`):

```yaml
  image_picker: ^1.1.2
  flutter_image_compress: ^2.3.0
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: `Got dependencies!` (resolver may bump transitive versions in `pubspec.lock` — that file is generated, commit it as-is, never hand-edit).

- [ ] **Step 3: Add iOS usage strings**

In `ios/Runner/Info.plist`, inside the top-level `<dict>` (e.g. right before the closing `</dict>`), add:

```xml
	<key>NSCameraUsageDescription</key>
	<string>Closr uses the camera to photograph products for your catalog.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Closr uses your photo library to add product photos to your catalog.</string>
```

(Android needs no manifest change — `image_picker` uses the system photo picker / camera intent.)

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: same 7 pre-existing infos/warnings (deprecated `withOpacity` in legacy screens, one unused variable) — **no new issues**.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist
git commit -m "chore(deps): add image_picker + flutter_image_compress for catalog photos"
```

---

## Task 2: Product model (TDD)

**Files:**
- Create: `lib/features/catalog/data/product.dart`
- Test: `test/features/catalog/product_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/product_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';

void main() {
  group('Product', () {
    test('round-trips through toMap/fromMap', () {
      final original = Product(
        name: 'Banarasi Silk Saree',
        description: 'Deep red, gold zari border',
        price: 4500,
        images: ['uid/1.jpg', 'uid/2.jpg'],
        isUnique: true,
        pieceStatus: 'booked',
      );
      final restored = Product.fromMap(original.toMap());
      expect(restored.name, 'Banarasi Silk Saree');
      expect(restored.description, 'Deep red, gold zari border');
      expect(restored.price, 4500);
      expect(restored.images, ['uid/1.jpg', 'uid/2.jpg']);
      expect(restored.isUnique, isTrue);
      expect(restored.pieceStatus, 'booked');
    });

    test('fromMap tolerates missing optional fields', () {
      final p = Product.fromMap({'name': 'Cotton Kurti'});
      expect(p.name, 'Cotton Kurti');
      expect(p.images, isEmpty);
      expect(p.price, 0);
      expect(p.unit, 'pc');
      expect(p.isUnique, isFalse);
      expect(p.pieceStatus, 'available');
      expect(p.qtyOnHand, 0);
      expect(p.active, isTrue);
    });

    test('fromMap parses numeric strings from Postgres', () {
      final p = Product.fromMap(
        {'name': 'X', 'price': '1499.50', 'qty_on_hand': '3'},
      );
      expect(p.price, 1499.50);
      expect(p.qtyOnHand, 3);
    });

    test('unique piece availability follows piece_status', () {
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'available').isAvailable,
        isTrue,
      );
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'booked').isAvailable,
        isFalse,
      );
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'sold').isAvailable,
        isFalse,
      );
    });

    test('stocked availability follows qty_on_hand', () {
      expect(Product(name: 'A', qtyOnHand: 2).isAvailable, isTrue);
      expect(Product(name: 'A', qtyOnHand: 0).isAvailable, isFalse);
    });

    test('coverImage is first image or null', () {
      expect(Product(name: 'A', images: ['u/a.jpg']).coverImage, 'u/a.jpg');
      expect(Product(name: 'A').coverImage, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/product_test.dart`
Expected: FAIL — compile error, `product.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/catalog/data/product.dart`:

```dart
/// A catalog product. `isUnique` pieces track availability via [pieceStatus]
/// (available/booked/sold); stocked items track [qtyOnHand].
class Product {
  const Product({
    this.id,
    required this.name,
    this.description,
    this.sku,
    this.images = const [],
    this.price = 0,
    this.unit = 'pc',
    this.gstRate,
    this.isUnique = false,
    this.pieceStatus = 'available',
    this.qtyOnHand = 0,
    this.active = true,
    this.createdAt,
  });

  final String? id;
  final String name;
  final String? description;
  final String? sku;
  final List<String> images;
  final double price;
  final String unit;
  final double? gstRate;
  final bool isUnique;
  final String pieceStatus;
  final int qtyOnHand;
  final bool active;
  final DateTime? createdAt;

  bool get isAvailable => isUnique ? pieceStatus == 'available' : qtyOnHand > 0;

  String? get coverImage => images.isEmpty ? null : images.first;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static double? _asDoubleOrNull(dynamic v) {
    if (v == null) return null;
    return v is num ? v.toDouble() : double.tryParse(v.toString());
  }

  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
      sku: map['sku']?.toString(),
      images:
          (map['images'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      price: _asDouble(map['price']),
      unit: (map['unit'] ?? 'pc').toString(),
      gstRate: _asDoubleOrNull(map['gst_rate']),
      isUnique: map['is_unique'] == true,
      pieceStatus: (map['piece_status'] ?? 'available').toString(),
      qtyOnHand: _asInt(map['qty_on_hand'], 0),
      active: map['active'] != false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'sku': sku,
        'images': images,
        'price': price,
        'unit': unit,
        'gst_rate': gstRate,
        'is_unique': isUnique,
        'piece_status': pieceStatus,
        'qty_on_hand': qtyOnHand,
        'active': active,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/product_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/data/product.dart test/features/catalog/product_test.dart
git commit -m "feat(catalog): add Product model with availability logic"
```

---

## Task 3: SignedUrlCache (TDD)

**Files:**
- Create: `lib/features/catalog/data/signed_url_cache.dart`
- Test: `test/features/catalog/signed_url_cache_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/signed_url_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/signed_url_cache.dart';

void main() {
  group('SignedUrlCache', () {
    test('returns null on miss', () {
      final cache = SignedUrlCache();
      expect(cache.get('u/a.jpg'), isNull);
    });

    test('returns stored url before expiry', () {
      var now = DateTime(2026, 1, 1, 12, 0);
      final cache = SignedUrlCache(
        ttl: const Duration(hours: 1),
        clock: () => now,
      );
      cache.put('u/a.jpg', 'https://signed/a');
      now = DateTime(2026, 1, 1, 12, 50);
      expect(cache.get('u/a.jpg'), 'https://signed/a');
    });

    test('drops urls within the refresh margin of expiry', () {
      var now = DateTime(2026, 1, 1, 12, 0);
      final cache = SignedUrlCache(
        ttl: const Duration(hours: 1),
        refreshMargin: const Duration(minutes: 5),
        clock: () => now,
      );
      cache.put('u/a.jpg', 'https://signed/a');
      now = DateTime(2026, 1, 1, 12, 56); // expiry 13:00, inside 5-min margin
      expect(cache.get('u/a.jpg'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/signed_url_cache_test.dart`
Expected: FAIL — `signed_url_cache.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/catalog/data/signed_url_cache.dart`:

```dart
/// In-memory cache for signed storage URLs. Entries are dropped shortly
/// before their real expiry so callers re-sign instead of serving a URL
/// that dies mid-render.
class SignedUrlCache {
  SignedUrlCache({
    this.ttl = const Duration(hours: 1),
    this.refreshMargin = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final Duration refreshMargin;
  final DateTime Function() _clock;
  final Map<String, _Entry> _entries = {};

  String? get(String path) {
    final entry = _entries[path];
    if (entry == null) return null;
    if (_clock().isAfter(entry.expiresAt.subtract(refreshMargin))) {
      _entries.remove(path);
      return null;
    }
    return entry.url;
  }

  void put(String path, String url) {
    _entries[path] = _Entry(url, _clock().add(ttl));
  }
}

class _Entry {
  _Entry(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/catalog/signed_url_cache_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/catalog/data/signed_url_cache.dart test/features/catalog/signed_url_cache_test.dart
git commit -m "feat(catalog): add SignedUrlCache with pre-expiry refresh"
```

---

## Task 4: ProductsService + providers

**Files:**
- Create: `lib/features/catalog/data/products_service.dart`
- Create: `lib/features/catalog/controller/products_provider.dart`

No unit tests here — the service is a thin Supabase/platform wrapper (same convention as `BusinessProfileService`); logic worth testing lives in `Product` and `SignedUrlCache`.

- [ ] **Step 1: Create the service**

Create `lib/features/catalog/data/products_service.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product.dart';
import 'signed_url_cache.dart';

class ProductsService {
  ProductsService({SupabaseClient? client, SignedUrlCache? urlCache})
      : _supabase = client ?? Supabase.instance.client,
        _urlCache = urlCache ?? SignedUrlCache();

  static const _bucket = 'product-images';
  static const _signedUrlTtlSeconds = 3600;

  final SupabaseClient _supabase;
  final SignedUrlCache _urlCache;

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.id;
  }

  Future<List<Product>> fetchProducts() async {
    final rows = await _supabase
        .from('products')
        .select()
        .eq('user_id', _userId)
        .eq('active', true)
        .order('created_at', ascending: false);
    return rows.map<Product>((r) => Product.fromMap(r)).toList();
  }

  Future<Product> addProduct(Product product) async {
    final row = await _supabase
        .from('products')
        .insert({...product.toMap(), 'user_id': _userId})
        .select()
        .single();
    return Product.fromMap(row);
  }

  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async {
    final row = await _supabase
        .from('products')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId)
        .select()
        .single();
    return Product.fromMap(row);
  }

  /// Soft delete — orders may reference products, so rows are never removed.
  Future<void> archiveProduct(String id) async {
    await updateProduct(id, {'active': false});
  }

  /// Compresses and uploads one local photo; returns its storage path.
  Future<String> uploadImage(String localPath) async {
    final bytes = await _compress(localPath);
    final path =
        '$_userId/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.jpg';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<Uint8List> _compress(String localPath) async {
    final result = await FlutterImageCompress.compressWithFile(
      localPath,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      throw StateError('Could not read image at $localPath');
    }
    return result;
  }

  /// Short-lived signed URL for a private storage path (cached until near
  /// expiry — the bucket is private, paths are never served raw).
  Future<String> signedUrl(String path) async {
    final cached = _urlCache.get(path);
    if (cached != null) return cached;
    final url = await _supabase.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlTtlSeconds);
    _urlCache.put(path, url);
    return url;
  }
}
```

- [ ] **Step 2: Create the controller + providers**

Create `lib/features/catalog/controller/products_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/product.dart';
import '../data/products_service.dart';

final productsServiceProvider =
    Provider<ProductsService>((ref) => ProductsService());

final productsControllerProvider =
    StateNotifierProvider<ProductsController, AsyncValue<List<Product>>>((ref) {
  return ProductsController(ref.watch(productsServiceProvider))..load();
});

/// Signed URL for a storage path; family-cached per path.
final productImageUrlProvider =
    FutureProvider.family<String, String>((ref, path) {
  return ref.watch(productsServiceProvider).signedUrl(path);
});

class ProductsController extends StateNotifier<AsyncValue<List<Product>>> {
  ProductsController(this._service) : super(const AsyncValue.loading());

  final ProductsService _service;

  Future<void> load() async {
    state = await AsyncValue.guard(_service.fetchProducts);
  }

  Future<void> addProduct(Product product) async {
    await _service.addProduct(product);
    await load();
  }

  Future<void> updateProduct(String id, Map<String, dynamic> changes) async {
    await _service.updateProduct(id, changes);
    await load();
  }

  Future<void> setPieceStatus(String id, String status) =>
      updateProduct(id, {'piece_status': status});

  Future<void> adjustQty(Product product, int delta) {
    final next = product.qtyOnHand + delta;
    return updateProduct(product.id!, {'qty_on_hand': next < 0 ? 0 : next});
  }

  Future<void> archive(String id) async {
    await _service.archiveProduct(id);
    await load();
  }
}
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/features/catalog`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/catalog/data/products_service.dart lib/features/catalog/controller/products_provider.dart
git commit -m "feat(catalog): add ProductsService and Riverpod providers"
```

---

## Task 5: ProductImage + ProductTile widgets (TDD)

**Files:**
- Create: `lib/features/catalog/widgets/product_image.dart`
- Create: `lib/features/catalog/widgets/product_tile.dart`
- Test: `test/features/catalog/product_tile_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/catalog/product_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/widgets/product_tile.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, height: 280, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows name, INR price and availability pill for a unique piece',
      (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(
        name: 'Banarasi Saree',
        price: 4500,
        isUnique: true,
        pieceStatus: 'available',
      ),
      onTap: () {},
    )));
    expect(find.text('Banarasi Saree'), findsOneWidget);
    expect(find.text('₹4,500'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('shows stock count for a stocked item', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799, qtyOnHand: 4),
      onTap: () {},
    )));
    expect(find.text('4 in stock'), findsOneWidget);
  });

  testWidgets('shows sold-out state for stocked item with zero qty',
      (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799, qtyOnHand: 0),
      onTap: () {},
    )));
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('shows placeholder when the product has no photo',
      (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799),
      onTap: () {},
    )));
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/catalog/product_tile_test.dart`
Expected: FAIL — `product_tile.dart` does not exist.

- [ ] **Step 3: Create ProductImage**

Create `lib/features/catalog/widgets/product_image.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

import '../controller/products_provider.dart';

/// Renders a private-storage product photo via a signed URL, with a quiet
/// placeholder for missing/loading/error states.
class ProductImage extends ConsumerWidget {
  const ProductImage({super.key, this.path, this.iconSize = 34});

  final String? path;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    if (p == null) return _placeholder();

    final url = ref.watch(productImageUrlProvider(p));
    return url.when(
      data: (u) => Image.network(
        u,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
      loading: () => _placeholder(),
      error: (_, __) => _placeholder(),
    );
  }

  Widget _placeholder() {
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
}
```

- [ ] **Step 4: Create ProductTile**

Create `lib/features/catalog/widgets/product_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

import '../data/product.dart';
import 'product_image.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(path: product.coverImage),
                  if (product.isUnique)
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: StatusPill(status: product.pieceStatus),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Money.inr(product.price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (!product.isUnique)
                        Text(
                          product.qtyOnHand > 0
                              ? '${product.qtyOnHand} in stock'
                              : 'Out of stock',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: product.qtyOnHand > 0
                                ? AppColors.textSecondary
                                : AppColors.danger,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/catalog/product_tile_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/catalog/widgets/product_image.dart lib/features/catalog/widgets/product_tile.dart test/features/catalog/product_tile_test.dart
git commit -m "feat(catalog): add ProductImage and ProductTile widgets"
```

---

## Task 6: Catalog screen + navigation wiring

**Files:**
- Create: `lib/features/catalog/widgets/catalog_empty_state.dart`
- Create: `lib/features/catalog/presentation/catalog_screen.dart`
- Modify: `lib/shared/widgets/app_bottom_nav.dart` (add 4th item)
- Modify: `lib/main.dart` (add tab + context-aware FAB)

Note: `catalog_screen.dart` imports `product_detail_screen.dart` and `product_form_screen.dart` which are created in Tasks 7–8. To keep every commit compiling, this task creates both as minimal placeholders that Tasks 7–8 fill in.

- [ ] **Step 1: Create the empty state**

Create `lib/features/catalog/widgets/catalog_empty_state.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Your catalog is empty',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Snap a photo of your first piece — your catalog is your storefront.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add your first piece'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create placeholder form + detail screens (filled in Tasks 7–8)**

Create `lib/features/catalog/presentation/product_form_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/product.dart';

/// Placeholder — full implementation in the ProductFormScreen task.
class ProductFormScreen extends StatelessWidget {
  const ProductFormScreen({super.key, this.existing});

  final Product? existing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? 'Add piece' : 'Edit piece')),
      body: const Center(child: Text('Coming in the next commit')),
    );
  }
}
```

Create `lib/features/catalog/presentation/product_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/product.dart';

/// Placeholder — full implementation in the ProductDetailScreen task.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: const Center(child: Text('Coming in the next commit')),
    );
  }
}
```

- [ ] **Step 3: Create the catalog screen**

Create `lib/features/catalog/presentation/catalog_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/products_provider.dart';
import '../data/product.dart';
import '../widgets/catalog_empty_state.dart';
import '../widgets/product_tile.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  void _openForm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Catalog',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: () => _openForm(context),
                  icon: const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Add piece',
                ),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                onRetry: () =>
                    ref.read(productsControllerProvider.notifier).load(),
              ),
              data: (products) => products.isEmpty
                  ? CatalogEmptyState(onAdd: () => _openForm(context))
                  : _grid(context, ref, products),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<Product> products) {
    return RefreshIndicator(
      onRefresh: () => ref.read(productsControllerProvider.notifier).load(),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          96, // clears the FAB
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.72,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductTile(
            product: product,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Could not load your catalog.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add the Catalog item to the bottom nav**

In `lib/shared/widgets/app_bottom_nav.dart`, replace the `Row` children (lines ~31-39) with:

```dart
          children: [
            Expanded(child: navItem(Icons.home_rounded, "Home", 0)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.people_alt_rounded, "Leads", 1)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.shopping_bag_rounded, "Orders", 2)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.storefront_rounded, "Catalog", 3)),
          ],
```

- [ ] **Step 5: Wire the tab + context-aware FAB in main.dart**

In `lib/main.dart`:

1. Add imports:

```dart
import 'features/catalog/presentation/catalog_screen.dart';
import 'features/catalog/presentation/product_form_screen.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
```

2. In `_MainScreenState.initState`, add the catalog screen to `_screens`:

```dart
    _screens = [
      DashboardScreen(onNavigate: changeTab),
      const LeadsScreen(),
      OrdersScreen(),
      const CatalogScreen(),
    ];
```

3. Replace the `floatingActionButton:` block with a context-aware FAB (on the Catalog tab it adds a product; elsewhere it keeps the existing add-entry sheet), swapping the hardcoded `Colors.deepPurple` for the token:

```dart
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          if (currentIndex == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductFormScreen()),
            );
            return;
          }
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const AddEntryScreen(),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
```

- [ ] **Step 6: Verify compile + full test suite**

Run: `flutter analyze lib/features/catalog lib/main.dart lib/shared/widgets/app_bottom_nav.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/catalog lib/main.dart lib/shared/widgets/app_bottom_nav.dart
git commit -m "feat(catalog): add catalog grid tab with empty state and nav wiring"
```

---

## Task 7: ProductFormScreen (add/edit with photos)

**Files:**
- Modify: `lib/features/catalog/presentation/product_form_screen.dart` (replace the placeholder entirely)

- [ ] **Step 1: Replace the placeholder with the full form**

Replace the entire contents of `lib/features/catalog/presentation/product_form_screen.dart` with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';

import '../controller/products_provider.dart';
import '../data/product.dart';
import '../widgets/product_image.dart';

const _maxPhotos = 5;

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing});

  /// When set, the form edits this product instead of creating a new one.
  final Product? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _qty;

  late bool _isUnique;
  late List<String> _existingImages; // storage paths already uploaded
  final List<XFile> _newPhotos = []; // picked locally, uploaded on save
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  int get _photoCount => _existingImages.length + _newPhotos.length;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
      text: p == null
          ? ''
          : (p.price == p.price.roundToDouble()
              ? p.price.toStringAsFixed(0)
              : p.price.toString()),
    );
    _description = TextEditingController(text: p?.description ?? '');
    _qty = TextEditingController(text: (p?.qtyOnHand ?? 1).toString());
    _isUnique = p?.isUnique ?? true;
    _existingImages = List.of(p?.images ?? const []);
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _description, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 92);
      if (file != null && mounted) {
        setState(() => _newPhotos.add(file));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera or gallery.')),
      );
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final controller = ref.read(productsControllerProvider.notifier);
    final service = ref.read(productsServiceProvider);

    try {
      final uploaded = <String>[];
      for (final photo in _newPhotos) {
        uploaded.add(await service.uploadImage(photo.path));
      }
      final images = [..._existingImages, ...uploaded];

      final name = _name.text.trim();
      final price = double.parse(_price.text.trim());
      final description =
          _description.text.trim().isEmpty ? null : _description.text.trim();
      final qty = _isUnique ? 0 : int.parse(_qty.text.trim());

      if (_isEdit) {
        await controller.updateProduct(widget.existing!.id!, {
          'name': name,
          'price': price,
          'description': description,
          'is_unique': _isUnique,
          'qty_on_hand': qty,
          'images': images,
        });
      } else {
        await controller.addProduct(Product(
          name: name,
          price: price,
          description: description,
          isUnique: _isUnique,
          qtyOnHand: qty,
          images: images,
        ));
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Piece updated' : 'Added to catalog')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit piece' : 'Add piece'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _photoStrip(),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('Price (₹)'),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return 'Enter a valid price';
                if (parsed < 0) return 'Price cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Description (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SwitchListTile(
              value: _isUnique,
              onChanged: (v) => setState(() => _isUnique = v),
              activeTrackColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'One-of-a-kind piece',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: _isEdit ? 'Save changes' : 'Add to catalog',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      );

  Widget _photoStrip() {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _existingImages.length; i++)
            _thumb(
              child: ProductImage(path: _existingImages[i], iconSize: 22),
              onRemove: () => setState(() => _existingImages.removeAt(i)),
            ),
          for (var i = 0; i < _newPhotos.length; i++)
            _thumb(
              child: Image.file(File(_newPhotos[i].path), fit: BoxFit.cover),
              onRemove: () => setState(() => _newPhotos.removeAt(i)),
            ),
          if (_photoCount < _maxPhotos)
            GestureDetector(
              onTap: _showPhotoSourceSheet,
              child: Container(
                width: 96,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
                    SizedBox(height: 4),
                    Text(
                      'Add photo',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: child,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compile + tests**

Run: `flutter analyze lib/features/catalog`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/features/catalog/presentation/product_form_screen.dart
git commit -m "feat(catalog): add product form with camera/gallery photos and stock toggle"
```

---

## Task 8: ProductDetailScreen (gallery, status, qty, archive)

**Files:**
- Modify: `lib/features/catalog/presentation/product_detail_screen.dart` (replace the placeholder entirely)

- [ ] **Step 1: Replace the placeholder with the full screen**

Replace the entire contents of `lib/features/catalog/presentation/product_detail_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../controller/products_provider.dart';
import '../data/product.dart';
import '../widgets/product_image.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.product});

  /// Snapshot used until the live list provides a fresher row.
  final Product product;

  Product _current(WidgetRef ref) {
    final products = ref.watch(productsControllerProvider).valueOrNull;
    if (products == null) return product;
    for (final p in products) {
      if (p.id == product.id) return p;
    }
    return product;
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this piece?'),
        content: const Text(
          'It will disappear from your catalog but stays on past orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Archive',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(productsControllerProvider.notifier).archive(product.id!);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Piece archived')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = _current(ref);
    final controller = ref.read(productsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductFormScreen(existing: p),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _confirmArchive(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          _gallery(p),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Money.inr(p.price),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.money,
                  ),
                ),
                if ((p.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    p.description!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: p.isUnique
                      ? _pieceStatusControl(p, controller)
                      : _stockControl(p, controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallery(Product p) {
    if (p.images.isEmpty) {
      return const SizedBox(height: 280, child: ProductImage(path: null));
    }
    return SizedBox(
      height: 340,
      child: PageView(
        children: [
          for (final path in p.images) ProductImage(path: path),
        ],
      ),
    );
  }

  Widget _pieceStatusControl(Product p, ProductsController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Availability',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'available', label: Text('Available')),
              ButtonSegment(value: 'booked', label: Text('Booked')),
              ButtonSegment(value: 'sold', label: Text('Sold')),
            ],
            selected: {p.pieceStatus},
            onSelectionChanged: (selection) {
              controller.setPieceStatus(p.id!, selection.first);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Booked reserves the piece so it cannot be sold twice.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _stockControl(Product p, ProductsController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('In stock', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            IconButton(
              onPressed:
                  p.qtyOnHand > 0 ? () => controller.adjustQty(p, -1) : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.primary,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${p.qtyOnHand}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => controller.adjustQty(p, 1),
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.primary,
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify compile + tests**

Run: `flutter analyze lib/features/catalog`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/features/catalog/presentation/product_detail_screen.dart
git commit -m "feat(catalog): add product detail with gallery, availability and stock controls"
```

---

## Task 9: Full gate + manual smoke test

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: all tests pass — 17 pre-existing + 6 (product) + 3 (signed-url cache) + 4 (product tile) = 30.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: only the 7 pre-existing infos/warnings in legacy files (`lead_card.dart`, `add_entry_screen.dart`). Zero issues in `lib/features/catalog`.

- [ ] **Step 3: Supabase security advisor**

Use MCP `get_advisors` type `security` on project `dgviploqkwyuttcdnddq`.
Expected: no new findings (this plan adds no DDL; `products` table + `product-images` bucket policies already exist from migrations 0001–0004).

- [ ] **Step 4: Manual smoke test on a device/simulator**

```bash
flutter run
```

Verify:
1. Log in → Catalog tab appears (4th tab) → empty state with "Add your first piece".
2. Add a unique piece with a gallery photo + price → appears in grid with "Available" pill, ₹ price.
3. Tap tile → detail shows photo, price; switch status to Booked → pill updates in grid.
4. Add a stocked item (toggle off one-of-a-kind, qty 4) → grid shows "4 in stock"; +/- adjusts; at 0 shows "Out of stock" in red.
5. Edit: change price, add a second photo → detail gallery swipes between photos.
6. Archive from detail → confirm → gone from grid.
7. FAB on Catalog tab opens the add form; on other tabs it still opens the old add-entry sheet.
8. Kill + relaunch → catalog loads (signed URLs re-issued fine).

- [ ] **Step 5: Final commit if anything changed**

```bash
git add -A
git commit -m "chore(catalog): green tests + clean analyze for catalog slice"
```

---

## Self-review notes (against the spec)

- **Catalog (spec §6):** image-first 2-col grid, add via snap/upload + price, Available/Booked/Sold pill on unique pieces, qty on stocked items. "Create enquiry from product" deferred to stage 3 (needs customers) — noted in header. ✅
- **Data model (spec §4):** uses the existing `products` table exactly (`images text[]`, `is_unique`, `piece_status`, `qty_on_hand`, `active`); no schema change. Soft-delete via `active=false` keeps order references safe. ✅
- **Storage (spec §5):** private `product-images` bucket, paths under `<user_id>/`, compression on upload (1600px / q82 JPEG), display via signed URLs with pre-expiry cache. ✅
- **Security (spec §8):** no new tables/policies; storage writes scoped by existing owner policies; no service_role; input validation on price/qty. ✅
- **UI/UX (spec §7):** tokens everywhere, `ProductTile` from the component kit, `StatusPill` reused, photo-forward tiles + hero gallery, empty state with personality. ✅
- **Testing (spec §10):** availability transitions + model parsing + URL-cache expiry unit-tested; tile widget-tested. Service is a thin wrapper, untested by convention. ✅
- **Navigation (spec §6):** 4th "Catalog" tab; FAB is context-aware. Leads→Enquiries rename deferred to stage 3. ✅
