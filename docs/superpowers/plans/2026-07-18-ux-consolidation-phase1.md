# UX Consolidation Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove duplicate features, give every feature one home, expand Business Profile, add a dedicated Invoice Settings screen, fix logout via reactive routing, and tokenize the touched screens.

**Architecture:** Extend the existing `business_profile` table + typed `BusinessProfile` model/service (converging Profile off raw Supabase writes). Introduce a reactive `RootGate` that routes on `authProvider` so logout works from anywhere. Build shared design-system widgets and compose Profile / Settings / Invoice Settings from them.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + Storage), `qr_flutter`, `image_picker`, `flutter_image_compress`. Tests via `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-18-ux-consolidation-phase1-design.md`

**Conventions:**
- Run one test file: `flutter test test/path/to/test.dart`
- Analyze: `flutter analyze`
- Commit messages: Conventional Commits, end with the Co-Authored-By trailer.
- Work stays on branch `mvp_release` (established working branch).

---

## File Structure

**Data / migration**
- Create `supabase/migrations/20260718090000_business_profile_extend.sql` — new columns + storage bucket + policies.
- Modify `lib/features/business/data/business_profile.dart` — new fields, `fromMap`, `toMap`, `copyWith`.
- Modify `lib/features/business/data/business_profile_service.dart` — add `updateInvoiceNumbering`, `assetStoragePath` helper.
- Create `lib/features/business/data/business_asset_service.dart` — pick/compress/upload logo & signature.

**Shared design-system widgets**
- Create `lib/shared/widgets/settings_section.dart`
- Create `lib/shared/widgets/settings_tile.dart` (default / `comingSoon` / `danger` variants)
- Create `lib/shared/widgets/profile_field_row.dart`
- Create `lib/shared/widgets/app_screen_header.dart`

**Logout / navigation**
- Create `lib/shared/utils/session_actions.dart` — `confirmAndLogout(context, ref)`.
- Create `lib/app/root_gate.dart` — `RootGate` + pure `rootDestinationFor(...)`.
- Modify `lib/app/splash_screen.dart` — route into `RootGate`.

**Screens**
- Rewrite `lib/features/profile/presentation/profile_screen.dart`
- Create `lib/features/invoices/presentation/invoice_settings_screen.dart` (+ `InvoiceSettingsPreview` widget in same file)
- Rewrite `lib/features/settings/presentation/settings_screen.dart`
- Modify `lib/shared/components/help_and_support_screen.dart` — content refresh + tokens
- Modify `lib/features/business/presentation/business_hub_screen.dart` — tile wording

**Tests**
- `test/features/business/business_profile_test.dart` (extend existing)
- `test/features/business/business_asset_service_test.dart`
- `test/shared/widgets/settings_tile_test.dart`
- `test/shared/session_actions_test.dart`
- `test/app/root_gate_test.dart`
- `test/features/settings/settings_screen_test.dart` (rewrite existing)
- `test/features/profile/profile_screen_test.dart`
- `test/features/invoices/invoice_settings_screen_test.dart`
- `test/shared/components/help_support_screen_test.dart`

---

## Task 1: Database migration + storage

**Files:**
- Create: `supabase/migrations/20260718090000_business_profile_extend.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Phase 1 UX consolidation: extend business_profile for the expanded
-- Business Profile + Invoice Settings screens. All columns nullable / defaulted
-- so existing rows and pre-migration app builds keep working.

alter table public.business_profile
  add column if not exists owner_name             text,
  add column if not exists city                   text,
  add column if not exists state                  text,
  add column if not exists pincode                text,
  add column if not exists pan                    text,
  add column if not exists business_type          text,
  add column if not exists bank_account_name      text,
  add column if not exists bank_account_number    text,
  add column if not exists bank_ifsc              text,
  add column if not exists default_payment_method text,
  add column if not exists gst_enabled            boolean not null default false,
  add column if not exists payment_terms          text,
  add column if not exists invoice_footer         text,
  add column if not exists signature_url          text,
  add column if not exists language               text not null default 'en',
  add column if not exists timezone               text not null default 'Asia/Kolkata';

-- Storage bucket for business logo + signature uploads.
insert into storage.buckets (id, name, public)
values ('business-assets', 'business-assets', true)
on conflict (id) do nothing;

-- Owner can write only under their own uid/ prefix; public read (logos appear on
-- shared invoices).
create policy "business-assets read"
  on storage.objects for select
  using (bucket_id = 'business-assets');

create policy "business-assets write own"
  on storage.objects for insert
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "business-assets update own"
  on storage.objects for update
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Commit** (user applies the SQL to `dgviploqkwyuttcdnddq` manually — cannot be run from here)

```bash
git add supabase/migrations/20260718090000_business_profile_extend.sql
git commit -m "feat(db): extend business_profile for expanded profile + invoice settings"
```

---

## Task 2: Extend BusinessProfile model

**Files:**
- Modify: `lib/features/business/data/business_profile.dart`
- Test: `test/features/business/business_profile_test.dart`

- [ ] **Step 1: Add failing tests** (append inside the existing `group`)

```dart
    test('round-trips new profile fields through toMap/fromMap', () {
      final original = BusinessProfile(
        name: 'Sarees by Anu',
        ownerName: 'Anu',
        city: 'Surat',
        state: 'Gujarat',
        pincode: '395001',
        pan: 'ABCDE1234F',
        businessType: 'Boutique',
        bankAccountName: 'Anu',
        bankAccountNumber: '000111222',
        bankIfsc: 'HDFC0001',
        defaultPaymentMethod: 'upi',
        gstEnabled: true,
        paymentTerms: 'Due on delivery',
        invoiceFooter: 'Thank you!',
        signatureUrl: 'https://x/sig.png',
        language: 'hi',
        timezone: 'Asia/Kolkata',
      );
      final restored = BusinessProfile.fromMap(original.toMap());
      expect(restored.ownerName, 'Anu');
      expect(restored.pincode, '395001');
      expect(restored.gstEnabled, isTrue);
      expect(restored.defaultPaymentMethod, 'upi');
      expect(restored.invoiceFooter, 'Thank you!');
      expect(restored.language, 'hi');
    });

    test('fromMap defaults language/timezone/gstEnabled', () {
      final p = BusinessProfile.fromMap({'name': 'X'});
      expect(p.language, 'en');
      expect(p.timezone, 'Asia/Kolkata');
      expect(p.gstEnabled, isFalse);
    });

    test('toMap still omits server-managed numbering', () {
      final map = BusinessProfile(name: 'S', ownerName: 'A').toMap();
      expect(map.containsKey('next_invoice_number'), isFalse);
      expect(map.containsKey('invoice_prefix'), isFalse);
      expect(map['owner_name'], 'A');
    });
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: FAIL — named parameters `ownerName` etc. undefined.

- [ ] **Step 3: Implement — replace the whole file**

```dart
class BusinessProfile {
  const BusinessProfile({
    this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.upiId,
    this.upiName,
    this.gstin,
    this.defaultGstRate = 0,
    this.invoicePrefix = 'INV-',
    this.nextInvoiceNumber = 1,
    this.currency = 'INR',
    this.invoiceTemplate = 'classic',
    this.ownerName,
    this.city,
    this.state,
    this.pincode,
    this.pan,
    this.businessType,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.defaultPaymentMethod,
    this.gstEnabled = false,
    this.paymentTerms,
    this.invoiceFooter,
    this.signatureUrl,
    this.language = 'en',
    this.timezone = 'Asia/Kolkata',
  });

  final String? id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? upiId;
  final String? upiName;
  final String? gstin;
  final double defaultGstRate;
  final String invoicePrefix;
  final int nextInvoiceNumber;
  final String currency;
  final String invoiceTemplate;

  // Phase 1 additions
  final String? ownerName;
  final String? city;
  final String? state;
  final String? pincode;
  final String? pan;
  final String? businessType;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? defaultPaymentMethod;
  final bool gstEnabled;
  final String? paymentTerms;
  final String? invoiceFooter;
  final String? signatureUrl;
  final String language;
  final String timezone;

  bool get hasGst => (gstin ?? '').trim().isNotEmpty;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
  static bool _asBool(dynamic v) =>
      v is bool ? v : v?.toString().toLowerCase() == 'true';
  static String? _str(dynamic v) => v?.toString();

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      logoUrl: _str(map['logo_url']),
      address: _str(map['address']),
      phone: _str(map['phone']),
      email: _str(map['email']),
      upiId: _str(map['upi_id']),
      upiName: _str(map['upi_name']),
      gstin: _str(map['gstin']),
      defaultGstRate: _asDouble(map['default_gst_rate']),
      invoicePrefix: (map['invoice_prefix'] ?? 'INV-').toString(),
      nextInvoiceNumber: _asInt(map['next_invoice_number'], 1),
      currency: (map['currency'] ?? 'INR').toString(),
      invoiceTemplate: (map['invoice_template'] ?? 'classic').toString(),
      ownerName: _str(map['owner_name']),
      city: _str(map['city']),
      state: _str(map['state']),
      pincode: _str(map['pincode']),
      pan: _str(map['pan']),
      businessType: _str(map['business_type']),
      bankAccountName: _str(map['bank_account_name']),
      bankAccountNumber: _str(map['bank_account_number']),
      bankIfsc: _str(map['bank_ifsc']),
      defaultPaymentMethod: _str(map['default_payment_method']),
      gstEnabled: _asBool(map['gst_enabled']),
      paymentTerms: _str(map['payment_terms']),
      invoiceFooter: _str(map['invoice_footer']),
      signatureUrl: _str(map['signature_url']),
      language: (map['language'] ?? 'en').toString(),
      timezone: (map['timezone'] ?? 'Asia/Kolkata').toString(),
    );
  }

  /// Client-writable columns only. Deliberately omits invoice_prefix /
  /// next_invoice_number (DB-owned; bumped by assign_invoice_number). Use
  /// BusinessProfileService.updateInvoiceNumbering to change those.
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
        'owner_name': ownerName,
        'city': city,
        'state': state,
        'pincode': pincode,
        'pan': pan,
        'business_type': businessType,
        'bank_account_name': bankAccountName,
        'bank_account_number': bankAccountNumber,
        'bank_ifsc': bankIfsc,
        'default_payment_method': defaultPaymentMethod,
        'gst_enabled': gstEnabled,
        'payment_terms': paymentTerms,
        'invoice_footer': invoiceFooter,
        'signature_url': signatureUrl,
        'language': language,
        'timezone': timezone,
      };

  BusinessProfile copyWith({
    String? name,
    String? logoUrl,
    String? address,
    String? phone,
    String? email,
    String? upiId,
    String? upiName,
    String? gstin,
    double? defaultGstRate,
    String? currency,
    String? invoiceTemplate,
    String? ownerName,
    String? city,
    String? state,
    String? pincode,
    String? pan,
    String? businessType,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? defaultPaymentMethod,
    bool? gstEnabled,
    String? paymentTerms,
    String? invoiceFooter,
    String? signatureUrl,
    String? language,
    String? timezone,
  }) {
    return BusinessProfile(
      id: id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      upiId: upiId ?? this.upiId,
      upiName: upiName ?? this.upiName,
      gstin: gstin ?? this.gstin,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      invoicePrefix: invoicePrefix,
      nextInvoiceNumber: nextInvoiceNumber,
      currency: currency ?? this.currency,
      invoiceTemplate: invoiceTemplate ?? this.invoiceTemplate,
      ownerName: ownerName ?? this.ownerName,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      pan: pan ?? this.pan,
      businessType: businessType ?? this.businessType,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      gstEnabled: gstEnabled ?? this.gstEnabled,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      invoiceFooter: invoiceFooter ?? this.invoiceFooter,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: PASS (all, including pre-existing tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/business/data/business_profile.dart test/features/business/business_profile_test.dart
git commit -m "feat(business): extend BusinessProfile model with profile + invoice fields"
```

---

## Task 3: Service — invoice numbering update + asset path helper

**Files:**
- Modify: `lib/features/business/data/business_profile_service.dart`
- Test: `test/features/business/business_asset_service_test.dart`

- [ ] **Step 1: Add failing test for the storage path builder**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile_service.dart';

void main() {
  test('assetStoragePath namespaces by user id and kind', () {
    final path = BusinessProfileService.assetStoragePath(
      userId: 'user-123',
      kind: 'logo',
      extension: 'jpg',
    );
    expect(path.startsWith('user-123/logo-'), isTrue);
    expect(path.endsWith('.jpg'), isTrue);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/features/business/business_asset_service_test.dart`
Expected: FAIL — `assetStoragePath` undefined.

- [ ] **Step 3: Add methods to `BusinessProfileService`** (append inside the class)

```dart
  /// Path under the `business-assets` bucket. First segment = uid so the
  /// storage RLS policy authorizes the write.
  static String assetStoragePath({
    required String userId,
    required String kind, // 'logo' | 'signature'
    required String extension,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$userId/$kind-$ts.$extension';
  }

  /// Prefix + starting number are DB-owned and excluded from `toMap`. Update
  /// them explicitly (rare; only from Invoice Settings).
  Future<void> updateInvoiceNumbering({
    String? prefix,
    int? nextNumber,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    final patch = <String, dynamic>{
      if (prefix != null) 'invoice_prefix': prefix,
      if (nextNumber != null) 'next_invoice_number': nextNumber,
    };
    if (patch.isEmpty) return;
    await _supabase
        .from('business_profile')
        .update(patch)
        .eq('user_id', user.id);
  }
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/features/business/business_asset_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Create the asset upload service**

Create `lib/features/business/data/business_asset_service.dart`:

```dart
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_profile_service.dart';

/// Picks an image, compresses it, uploads to the `business-assets` bucket and
/// returns the public URL. Returns null if the user cancels the picker.
class BusinessAssetService {
  BusinessAssetService({ImagePicker? picker, SupabaseClient? client})
      : _picker = picker ?? ImagePicker(),
        _supabase = client ?? Supabase.instance.client;

  final ImagePicker _picker;
  final SupabaseClient _supabase;

  Future<String?> pickAndUpload({required String kind}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
    );
    if (picked == null) return null;

    final compressed = await FlutterImageCompress.compressWithFile(
      picked.path,
      quality: 70,
      minWidth: 512,
    );
    final bytes = compressed ?? await File(picked.path).readAsBytes();

    final path = BusinessProfileService.assetStoragePath(
      userId: user.id,
      kind: kind,
      extension: 'jpg',
    );
    await _supabase.storage.from('business-assets').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _supabase.storage.from('business-assets').getPublicUrl(path);
  }
}
```

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/business/data`
Expected: No issues.

```bash
git add lib/features/business/data/business_profile_service.dart lib/features/business/data/business_asset_service.dart test/features/business/business_asset_service_test.dart
git commit -m "feat(business): invoice numbering update + asset upload service"
```

---

## Task 4: Shared design-system widgets

**Files:**
- Create: `lib/shared/widgets/settings_section.dart`, `settings_tile.dart`, `profile_field_row.dart`, `app_screen_header.dart`
- Test: `test/shared/widgets/settings_tile_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/shared/widgets/settings_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('default tile fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(SettingsTile(
      icon: Icons.star,
      title: 'Go',
      onTap: () => tapped = true,
    )));
    await t.tap(find.text('Go'));
    expect(tapped, isTrue);
  });

  testWidgets('comingSoon tile is disabled and labelled', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(SettingsTile(
      icon: Icons.star,
      title: 'Theme',
      comingSoon: true,
      onTap: () => tapped = true,
    )));
    expect(find.text('Coming soon'), findsOneWidget);
    await t.tap(find.text('Theme'));
    expect(tapped, isFalse); // disabled
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/shared/widgets/settings_tile_test.dart`
Expected: FAIL — `settings_tile.dart` not found.

- [ ] **Step 3: Implement `settings_tile.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

/// One settings row. Variants: default, comingSoon (disabled + chip),
/// danger (destructive, e.g. logout).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.comingSoon = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool comingSoon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.primary;
    final enabled = !comingSoon && onTap != null;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? color : AppColors.textSecondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: danger ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
          : null,
      trailing: comingSoon
          ? Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text('Coming soon',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            )
          : (danger
              ? null
              : const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary)),
      onTap: enabled ? onTap : null,
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/shared/widgets/settings_tile_test.dart`
Expected: PASS.

- [ ] **Step 5: Implement `settings_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

/// A titled group of settings rows in one rounded card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.textSecondary),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: AppSpacing.lg, color: AppColors.border),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Implement `profile_field_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

/// Label + value row with an inline edit affordance. Read mode shows label +
/// value ("Not set" when empty); edit mode swaps in a TextField.
class ProfileFieldRow extends StatelessWidget {
  const ProfileFieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.isEditing,
    required this.controller,
    required this.onEdit,
    required this.onSave,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final String value;
  final bool isEditing;
  final TextEditingController controller;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: isEditing
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      labelText: label,
                      hintText: hint,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(value.isEmpty ? 'Not set' : value,
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.textPrimary)),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(isEditing ? Icons.check_rounded : Icons.edit_outlined,
                size: 18, color: AppColors.primary),
            onPressed: isEditing ? onSave : onEdit,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Implement `app_screen_header.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

/// Consistent AppBar for the settings-family screens.
AppBar appScreenHeader(String title) => AppBar(
      title: Text(title),
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    );
```

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze lib/shared/widgets test/shared/widgets`
Expected: No issues.

```bash
git add lib/shared/widgets/settings_section.dart lib/shared/widgets/settings_tile.dart lib/shared/widgets/profile_field_row.dart lib/shared/widgets/app_screen_header.dart test/shared/widgets/settings_tile_test.dart
git commit -m "feat(ui): shared settings/profile design-system widgets"
```

---

## Task 5: confirmAndLogout session action

**Files:**
- Create: `lib/shared/utils/session_actions.dart`
- Test: `test/shared/session_actions_test.dart`

- [ ] **Step 1: Write failing test** (dialog shows; Cancel dismisses without side effects)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/utils/session_actions.dart';

void main() {
  testWidgets('shows confirm dialog and cancels cleanly', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => confirmAndLogout(context, ref),
                child: const Text('Logout'),
              ),
            ),
          );
        }),
      ),
    ));
    await t.tap(find.text('Logout'));
    await t.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Log out?'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/shared/session_actions_test.dart`
Expected: FAIL — `session_actions.dart` not found.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';

/// Confirms, signs out, and clears cached business data. Navigation happens
/// reactively via RootGate watching authProvider — no imperative push here.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('You will need to sign in again to access your shop.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Log out',
              style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  await ref.read(authProvider.notifier).logout();

  // Clear cached business data so the next account starts clean.
  ref.invalidate(userProfileProvider);
  ref.invalidate(businessProfileProvider);
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/shared/session_actions_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/utils/session_actions.dart test/shared/session_actions_test.dart
git commit -m "feat(auth): shared confirmAndLogout action with cache clear"
```

---

## Task 6: RootGate reactive routing

**Files:**
- Create: `lib/app/root_gate.dart`
- Modify: `lib/app/splash_screen.dart`
- Test: `test/app/root_gate_test.dart`

- [ ] **Step 1: Write failing test for the pure routing function**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/app/root_gate.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';

void main() {
  test('not authenticated -> intro', () {
    expect(
      rootDestinationFor(
          authed: false, profile: const AsyncValue.data(null)),
      RootDestination.intro,
    );
  });

  test('authed but no profile -> setup', () {
    expect(
      rootDestinationFor(authed: true, profile: const AsyncValue.data(null)),
      RootDestination.setup,
    );
  });

  test('authed with profile -> main', () {
    expect(
      rootDestinationFor(
        authed: true,
        profile: AsyncValue.data(const BusinessProfile(name: 'Shop')),
      ),
      RootDestination.main,
    );
  });

  test('authed while profile loading -> loading', () {
    expect(
      rootDestinationFor(
          authed: true, profile: const AsyncValue.loading()),
      RootDestination.loading,
    );
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/app/root_gate_test.dart`
Expected: FAIL — `root_gate.dart` not found.

- [ ] **Step 3: Implement `root_gate.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/app/app_intro_screen.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/business/presentation/business_setup_screen.dart';
import 'package:orderly_app/main.dart';

enum RootDestination { loading, intro, setup, main }

/// Pure routing decision — unit tested.
RootDestination rootDestinationFor({
  required bool authed,
  required AsyncValue<BusinessProfile?> profile,
}) {
  if (!authed) return RootDestination.intro;
  return profile.when(
    data: (p) => p == null ? RootDestination.setup : RootDestination.main,
    loading: () => RootDestination.loading,
    error: (_, __) => RootDestination.main, // fail open into the app shell
  );
}

/// Watches auth + profile and renders the right root reactively. Logout flips
/// authProvider -> this rebuilds to the intro. Replaces imperative post-logout
/// navigation.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authProvider).isAuthenticated;
    final profile = ref.watch(businessProfileProvider);

    switch (rootDestinationFor(authed: authed, profile: profile)) {
      case RootDestination.intro:
        return const AppIntroScreen();
      case RootDestination.setup:
        return BusinessSetupScreen(
          onDone: () => ref.invalidate(businessProfileProvider),
        );
      case RootDestination.main:
        return const MainScreen();
      case RootDestination.loading:
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/app/root_gate_test.dart`
Expected: PASS.

- [ ] **Step 5: Route splash into RootGate**

In `lib/app/splash_screen.dart`: replace the business-setup + final `pushReplacement` block (the `if (isLoggedIn) { ... hasProfile ... }` branch and the trailing navigation) with a single replacement into `RootGate`. Concretely, replace the body of `_initApp` after `await authController.checkAuth();` with:

```dart
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RootGate()),
    );
```

Remove now-unused imports (`AuthService`, `BusinessSetupScreen`, `AppIntroScreen`, `MainScreen`) and add `import 'package:orderly_app/app/root_gate.dart';`. Keep the animation + `loadingText`. RootGate now owns the authed/profile/main decision.

- [ ] **Step 6: Analyze + run app boot smoke**

Run: `flutter analyze lib/app`
Expected: No issues (no unused imports).

- [ ] **Step 7: Commit**

```bash
git add lib/app/root_gate.dart lib/app/splash_screen.dart test/app/root_gate_test.dart
git commit -m "feat(nav): reactive RootGate so logout re-routes from anywhere"
```

---

## Task 7: Rewrite Settings screen

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Test: `test/features/settings/settings_screen_test.dart` (rewrite)

- [ ] **Step 1: Rewrite the test to the new IA**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/settings/presentation/settings_screen.dart';

Widget _wrap() => const ProviderScope(child: MaterialApp(home: SettingsScreen()));

void main() {
  testWidgets('shows Settings title and section headers', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('BUSINESS'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
  });

  testWidgets('Invoice Settings and Logout rows present', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Invoice Settings'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('Theme row shows Coming soon and is disabled', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Coming soon'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — section headers not found.

- [ ] **Step 3: Implement the rewritten screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/shared/components/help_and_support_screen.dart';
import 'package:orderly_app/shared/components/privacy_policy_screen.dart';
import 'package:orderly_app/shared/components/terms_screen.dart';
import 'package:orderly_app/shared/utils/session_actions.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';
import 'package:orderly_app/shared/widgets/settings_section.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget s) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => s));

    Future<void> mail(String subject) async {
      final uri = Uri.parse(
          'mailto:closrsupport@gmail.com?subject=${Uri.encodeComponent(subject)}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Settings'),
      body: ListView(
        children: [
          SettingsSection(title: 'General', children: [
            SettingsTile(
                icon: Icons.notifications_rounded,
                title: 'Notifications',
                onTap: () => push(const NotificationsScreen())),
            const SettingsTile(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle: 'English',
                comingSoon: true),
            const SettingsTile(
                icon: Icons.dark_mode_rounded,
                title: 'Theme',
                comingSoon: true),
          ]),
          SettingsSection(title: 'Business', children: [
            SettingsTile(
                icon: Icons.receipt_long_rounded,
                title: 'Invoice Settings',
                subtitle: 'Prefix, tax, currency, footer, logo',
                onTap: () => push(const InvoiceSettingsScreen())),
            SettingsTile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Payment Settings',
                subtitle: 'UPI, bank, default method',
                onTap: () => push(const ProfileScreen(scrollTo: ProfileAnchor.payment))),
            SettingsTile(
                icon: Icons.percent_rounded,
                title: 'Tax & GST',
                onTap: () => push(const InvoiceSettingsScreen())),
          ]),
          SettingsSection(title: 'Security', children: [
            SettingsTile(
                icon: Icons.privacy_tip_rounded,
                title: 'Data Privacy',
                onTap: () => push(const PrivacyPolicyScreen())),
            const SettingsTile(
                icon: Icons.verified_user_rounded,
                title: 'Permissions',
                comingSoon: true),
            const SettingsTile(
                icon: Icons.lock_rounded,
                title: 'Security',
                comingSoon: true),
          ]),
          SettingsSection(title: 'Support', children: [
            SettingsTile(
                icon: Icons.help_center_rounded,
                title: 'Help Center',
                onTap: () => push(const HelpSupportScreen())),
            SettingsTile(
                icon: Icons.support_agent_rounded,
                title: 'Contact Support',
                onTap: () => mail('Closr Support')),
            SettingsTile(
                icon: Icons.bug_report_rounded,
                title: 'Report a Bug',
                onTap: () => mail('Closr Bug Report')),
            SettingsTile(
                icon: Icons.lightbulb_rounded,
                title: 'Request a Feature',
                onTap: () => mail('Closr Feature Request')),
            const SettingsTile(
                icon: Icons.quiz_rounded, title: 'FAQs', comingSoon: true),
          ]),
          SettingsSection(title: 'About', children: [
            const SettingsTile(
                icon: Icons.info_rounded,
                title: 'App Version',
                subtitle: 'Closr 1.0.0'),
            SettingsTile(
                icon: Icons.description_rounded,
                title: 'Terms & Conditions',
                onTap: () => push(const TermsScreen())),
            SettingsTile(
                icon: Icons.policy_rounded,
                title: 'Privacy Policy',
                onTap: () => push(const PrivacyPolicyScreen())),
            SettingsTile(
                icon: Icons.code_rounded,
                title: 'Open Source Licenses',
                onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Closr',
                      applicationVersion: '1.0.0',
                    )),
          ]),
          SettingsSection(title: 'Account', children: [
            SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                danger: true,
                onTap: () => confirmAndLogout(context, ref)),
          ]),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
```

Note: `App Version` tile has no `onTap` — render it as a plain non-tappable tile (SettingsTile with `onTap: null` shows no chevron and is inert; acceptable). The `ProfileScreen(scrollTo:)` param + `ProfileAnchor` enum are defined in Task 8.

- [ ] **Step 4: Run — expect FAIL (compile)** because `InvoiceSettingsScreen` / `ProfileAnchor` don't exist yet.

This task's screen depends on Tasks 8 & 9. **Do not run the settings test until Tasks 8 and 9 are done.** Mark this task's test as the integration checkpoint at the end of Task 9. Commit the screen source now without running (it will compile after Tasks 8–9).

Actually to keep each task independently green, reorder: implement Task 8 (Profile, defines `ProfileAnchor`) and Task 9 (Invoice Settings) BEFORE running Task 7's test. Proceed to Task 8 now; return to run Task 7 Step 2 test at Task 9 Step 6.

- [ ] **Step 5: Commit (after Tasks 8–9 compile)**

```bash
git add lib/features/settings/presentation/settings_screen.dart test/features/settings/settings_screen_test.dart
git commit -m "feat(settings): rebuild Settings with full section IA + reactive logout"
```

---

## Task 8: Rewrite Business Profile screen

**Files:**
- Modify: `lib/features/profile/presentation/profile_screen.dart`
- Test: `test/features/profile/profile_screen_test.dart`

Design notes:
- `ProfileScreen({ProfileAnchor? scrollTo})` + `enum ProfileAnchor { payment }` so Settings→Payment can jump to the payment card (use a `GlobalKey` + `Scrollable.ensureVisible` in a post-frame callback).
- Reads `businessProfileProvider` (typed). Header name/email/avatar from `userProfileProvider` (auth metadata merge).
- Editing model: a local `Map<String,TextEditingController>` seeded from the profile; a single "Save" builds a `copyWith` and calls `BusinessProfileService.upsert`, then invalidates both providers. Show loading (spinner), saving (button disabled + progress), error (snackbar).
- QR: `QrImageView(data: upiUri)` where `upiUri = 'upi://pay?pa=<upiId>&pn=<name>'`, only when `upiId` non-empty.
- Logo/signature upload via `BusinessAssetService.pickAndUpload(kind:)`.

- [ ] **Step 1: Write failing widget test** (override providers with test data)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';

Widget _wrap() => ProviderScope(
      overrides: [
        businessProfileProvider.overrideWith((ref) async =>
            const BusinessProfile(
              name: 'Sarees by Anu',
              ownerName: 'Anu',
              upiId: 'anu@upi',
              city: 'Surat',
            )),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );

void main() {
  testWidgets('renders grouped business profile sections', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Business Information'), findsOneWidget);
    expect(find.text('Business Identity'), findsOneWidget);
    expect(find.text('Payment Details'), findsOneWidget);
    expect(find.text('Sarees by Anu'), findsWidgets);
  });

  testWidgets('does not show logout or help (moved to Settings)', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Logout'), findsNothing);
    expect(find.text('Help & Support'), findsNothing);
  });

  testWidgets('shows UPI QR when upiId present', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('upi-qr')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: FAIL — sections/keys not found.

- [ ] **Step 3: Implement the rewritten Profile screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_asset_service.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

enum ProfileAnchor { payment }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.scrollTo});
  final ProfileAnchor? scrollTo;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _paymentKey = GlobalKey();
  final _controllers = <String, TextEditingController>{};
  String? _editingField;
  bool _saving = false;
  BusinessProfile? _seeded;

  TextEditingController _ctl(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(BusinessProfile Function(BusinessProfile) edit) async {
    final current = _seeded;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      final service = ref.read(businessProfileServiceProvider);
      await service.upsert(edit(current));
      ref.invalidate(businessProfileProvider);
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _editingField = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✅')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
    }
  }

  Future<void> _uploadLogo() async {
    final url = await BusinessAssetService().pickAndUpload(kind: 'logo');
    if (url == null) return;
    await _save((p) => p.copyWith(logoUrl: url));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Business Profile'),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load profile')),
        data: (profile) {
          final p = profile ?? const BusinessProfile(name: 'Your Business');
          _seeded = p;
          if (widget.scrollTo == ProfileAnchor.payment) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _paymentKey.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
            });
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _header(p),
              _sectionCard('Business Information', [
                _field(p, 'business_name', 'Business Name', p.name,
                    (v) => (c) => c.copyWith(name: v)),
                _field(p, 'owner_name', 'Owner Name', p.ownerName ?? '',
                    (v) => (c) => c.copyWith(ownerName: v)),
                _field(p, 'phone', 'Phone', p.phone ?? '',
                    (v) => (c) => c.copyWith(phone: v),
                    keyboardType: TextInputType.phone),
                _field(p, 'email', 'Email', p.email ?? '',
                    (v) => (c) => c.copyWith(email: v),
                    keyboardType: TextInputType.emailAddress),
                _field(p, 'address', 'Address', p.address ?? '',
                    (v) => (c) => c.copyWith(address: v)),
                _field(p, 'city', 'City', p.city ?? '',
                    (v) => (c) => c.copyWith(city: v)),
                _field(p, 'state', 'State', p.state ?? '',
                    (v) => (c) => c.copyWith(state: v)),
                _field(p, 'pincode', 'Pincode', p.pincode ?? '',
                    (v) => (c) => c.copyWith(pincode: v),
                    keyboardType: TextInputType.number),
              ]),
              _sectionCard('Business Identity', [
                _field(p, 'gstin', 'GST Number (optional)', p.gstin ?? '',
                    (v) => (c) => c.copyWith(gstin: v)),
                _field(p, 'pan', 'PAN (optional)', p.pan ?? '',
                    (v) => (c) => c.copyWith(pan: v)),
                _field(p, 'business_type', 'Business Type', p.businessType ?? '',
                    (v) => (c) => c.copyWith(businessType: v)),
                ListTile(
                  leading: const Icon(Icons.image_rounded, color: AppColors.primary),
                  title: const Text('Business Logo'),
                  subtitle: Text(p.logoUrl == null ? 'Not set' : 'Uploaded'),
                  trailing: TextButton(
                      onPressed: _saving ? null : _uploadLogo,
                      child: const Text('Upload')),
                ),
              ]),
              Container(key: _paymentKey),
              _sectionCard('Payment Details', [
                _field(p, 'upi_id', 'UPI ID', p.upiId ?? '',
                    (v) => (c) => c.copyWith(upiId: v)),
                _field(p, 'upi_name', 'UPI Name', p.upiName ?? '',
                    (v) => (c) => c.copyWith(upiName: v)),
                _field(p, 'bank_account_name', 'Bank Account Name (optional)',
                    p.bankAccountName ?? '',
                    (v) => (c) => c.copyWith(bankAccountName: v)),
                _field(p, 'bank_account_number', 'Bank Account Number (optional)',
                    p.bankAccountNumber ?? '',
                    (v) => (c) => c.copyWith(bankAccountNumber: v),
                    keyboardType: TextInputType.number),
                _field(p, 'bank_ifsc', 'IFSC (optional)', p.bankIfsc ?? '',
                    (v) => (c) => c.copyWith(bankIfsc: v)),
                if ((p.upiId ?? '').isNotEmpty) _qr(p),
              ]),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SettingsTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Invoice Settings',
                  subtitle: 'Prefix, tax, footer, logo',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen())),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BusinessProfile p) {
    final meta = ref.watch(userProfileProvider).value;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _saving ? null : _uploadLogo,
            child: CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.surfaceMuted,
              backgroundImage: p.logoUrl != null ? NetworkImage(p.logoUrl!) : null,
              child: p.logoUrl == null
                  ? const Icon(Icons.storefront_rounded, color: AppColors.primary)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(meta?['email'] ?? p.email ?? '',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                top: AppSpacing.lg, bottom: AppSpacing.sm, left: AppSpacing.xs),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BusinessProfile p,
    String key,
    String label,
    String value,
    BusinessProfile Function(String) Function(BusinessProfile) editFactory, {
    TextInputType? keyboardType,
  }) {
    // editFactory(v) returns a copyWith closure for the typed value.
    final editing = _editingField == key;
    final controller = _ctl(key, value);
    if (!editing) controller.text = value;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: editing
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        labelText: label),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(value.isEmpty ? 'Not set' : value,
                          style: const TextStyle(fontSize: 15)),
                    ],
                  ),
          ),
          _saving && editing
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: Icon(editing ? Icons.check_rounded : Icons.edit_outlined,
                      size: 18, color: AppColors.primary),
                  onPressed: () {
                    if (editing) {
                      _save(editFactory(controller.text.trim()));
                    } else {
                      setState(() => _editingField = key);
                    }
                  },
                ),
        ],
      ),
    );
  }

  Widget _qr(BusinessProfile p) {
    final uri = 'upi://pay?pa=${p.upiId}&pn=${Uri.encodeComponent(p.upiName ?? p.name)}';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const Text('UPI QR Preview',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          QrImageView(
            key: const Key('upi-qr'),
            data: uri,
            size: 140,
            backgroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/presentation/profile_screen.dart test/features/profile/profile_screen_test.dart
git commit -m "feat(profile): expand into grouped Business Profile via typed service"
```

---

## Task 9: Invoice Settings screen

**Files:**
- Create: `lib/features/invoices/presentation/invoice_settings_screen.dart`
- Test: `test/features/invoices/invoice_settings_screen_test.dart`

Design notes:
- Reads `businessProfileProvider`. Editable: prefix, starting number, GST toggle, default tax, currency, payment terms, footer. Logo/signature upload buttons.
- Prefix + starting number persist via `BusinessProfileService.updateInvoiceNumbering` (NOT upsert). All other fields persist via `upsert(copyWith(...))`.
- `InvoiceSettingsPreview`: lightweight styled card showing `<prefix><nextNumber>`, currency, tax %, footer — a live in-app mock (NOT a PDF; real PDFs remain on the Invoices screen).

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';

Widget _wrap() => ProviderScope(
      overrides: [
        businessProfileProvider.overrideWith((ref) async =>
            const BusinessProfile(
              name: 'Shop',
              invoicePrefix: 'INV-',
              nextInvoiceNumber: 42,
              currency: 'INR',
              invoiceFooter: 'Thank you',
            )),
      ],
      child: const MaterialApp(home: InvoiceSettingsScreen()),
    );

void main() {
  testWidgets('renders invoice settings fields and preview', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Invoice Settings'), findsWidgets);
    expect(find.text('Invoice Prefix'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.textContaining('INV-42'), findsWidgets); // preview number
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/features/invoices/invoice_settings_screen_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_asset_service.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';

class InvoiceSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceSettingsScreen({super.key});
  @override
  ConsumerState<InvoiceSettingsScreen> createState() => _State();
}

class _State extends ConsumerState<InvoiceSettingsScreen> {
  final _prefix = TextEditingController();
  final _startNo = TextEditingController();
  final _tax = TextEditingController();
  final _currency = TextEditingController();
  final _terms = TextEditingController();
  final _footer = TextEditingController();
  bool _gst = false;
  bool _saving = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in [_prefix, _startNo, _tax, _currency, _terms, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(BusinessProfile p) {
    if (_seeded) return;
    _prefix.text = p.invoicePrefix;
    _startNo.text = p.nextInvoiceNumber.toString();
    _tax.text = p.defaultGstRate.toString();
    _currency.text = p.currency;
    _terms.text = p.paymentTerms ?? '';
    _footer.text = p.invoiceFooter ?? '';
    _gst = p.gstEnabled;
    _seeded = true;
  }

  Future<void> _save(BusinessProfile p) async {
    setState(() => _saving = true);
    try {
      final service = ref.read(businessProfileServiceProvider);
      await service.upsert(p.copyWith(
        defaultGstRate: double.tryParse(_tax.text) ?? p.defaultGstRate,
        currency: _currency.text.trim().isEmpty ? p.currency : _currency.text.trim(),
        paymentTerms: _terms.text.trim(),
        invoiceFooter: _footer.text.trim(),
        gstEnabled: _gst,
      ));
      await service.updateInvoiceNumbering(
        prefix: _prefix.text.trim().isEmpty ? null : _prefix.text.trim(),
        nextNumber: int.tryParse(_startNo.text.trim()),
      );
      ref.invalidate(businessProfileProvider);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invoice settings saved ✅')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(businessProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Invoice Settings'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load settings')),
        data: (profile) {
          final p = profile ?? const BusinessProfile(name: 'Your Business');
          _seed(p);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _text('Invoice Prefix', _prefix),
              _text('Starting Invoice Number', _startNo,
                  keyboardType: TextInputType.number),
              SwitchListTile(
                title: const Text('GST Enabled'),
                value: _gst,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _gst = v),
              ),
              _text('Default Tax (%)', _tax,
                  keyboardType: TextInputType.number),
              _text('Currency', _currency),
              _text('Payment Terms', _terms),
              _text('Notes / Footer', _footer, maxLines: 3),
              const SizedBox(height: AppSpacing.lg),
              _uploadRow('Logo', 'logo'),
              _uploadRow('Signature', 'signature'),
              const SizedBox(height: AppSpacing.xl),
              const Text('Preview',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              InvoiceSettingsPreview(
                prefix: _prefix.text,
                number: int.tryParse(_startNo.text) ?? p.nextInvoiceNumber,
                currency: _currency.text,
                taxPct: double.tryParse(_tax.text) ?? 0,
                gstEnabled: _gst,
                footer: _footer.text,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(p),
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _text(String label, TextEditingController c,
      {TextInputType? keyboardType, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}), // live preview
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _uploadRow(String label, String kind) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
      title: Text('$label Upload'),
      trailing: TextButton(
        onPressed: _saving
            ? null
            : () async {
                final url =
                    await BusinessAssetService().pickAndUpload(kind: kind);
                if (url == null || !mounted) return;
                final p = ref.read(businessProfileProvider).value ??
                    const BusinessProfile(name: 'Your Business');
                await _save(kind == 'logo'
                    ? p.copyWith(logoUrl: url)
                    : p.copyWith(signatureUrl: url));
              },
        child: const Text('Upload'),
      ),
    );
  }
}

class InvoiceSettingsPreview extends StatelessWidget {
  const InvoiceSettingsPreview({
    super.key,
    required this.prefix,
    required this.number,
    required this.currency,
    required this.taxPct,
    required this.gstEnabled,
    required this.footer,
  });

  final String prefix;
  final int number;
  final String currency;
  final double taxPct;
  final bool gstEnabled;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$prefix$number',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text('Currency: $currency',
              style: const TextStyle(color: AppColors.textSecondary)),
          if (gstEnabled)
            Text('GST @ ${taxPct.toStringAsFixed(taxPct % 1 == 0 ? 0 : 2)}%',
                style: const TextStyle(color: AppColors.textSecondary)),
          if (footer.trim().isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            Text(footer, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/features/invoices/invoice_settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/invoices/presentation/invoice_settings_screen.dart test/features/invoices/invoice_settings_screen_test.dart
git commit -m "feat(invoices): dedicated Invoice Settings screen with live preview"
```

- [ ] **Step 6: Run Task 7's Settings test now (deferred integration checkpoint)**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS (InvoiceSettingsScreen + ProfileAnchor now exist). Then commit Task 7 (its Step 5).

---

## Task 10: Help & Support content refresh + tokenize

**Files:**
- Modify: `lib/shared/components/help_and_support_screen.dart`
- Test: `test/shared/components/help_support_screen_test.dart`

- [ ] **Step 1: Write failing test for the new, app-accurate content**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/components/help_and_support_screen.dart';

void main() {
  testWidgets('help content reflects the real Closr workflow', (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpSupportScreen()));
    await t.pumpAndSettle();
    expect(find.text('Capture a lead'), findsOneWidget);
    expect(find.text('Work in Focus Mode'), findsOneWidget);
    expect(find.text('Record payments'), findsOneWidget);
    expect(find.text('Share invoices'), findsOneWidget);
    expect(find.text('Contact Support'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/shared/components/help_support_screen_test.dart`
Expected: FAIL — new titles absent.

- [ ] **Step 3: Update the Quick Help list + tokenize**

In `help_and_support_screen.dart`, replace the five `_HelpItem`s in the Quick Help card with the app-accurate set below, and replace hardcoded colors (`Colors.deepPurple` → `AppColors.primary`, `Colors.grey` → `AppColors.textSecondary`, radius `16` → `AppRadius.md`, white → `AppColors.surface`). Add `import 'package:orderly_app/core/theme/app_colors.dart';` and `app_spacing.dart`.

```dart
const [
  _HelpItem(
    icon: Icons.bolt_rounded,
    title: 'Capture a lead',
    subtitle: 'Paste a WhatsApp message or use voice — Closr logs the enquiry.',
  ),
  Divider(),
  _HelpItem(
    icon: Icons.today_rounded,
    title: 'Work your day',
    subtitle: 'Today shows all your orders and enquiries in one pipeline.',
  ),
  Divider(),
  _HelpItem(
    icon: Icons.center_focus_strong_rounded,
    title: 'Work in Focus Mode',
    subtitle: 'Start My Work to handle items one at a time, distraction-free.',
  ),
  Divider(),
  _HelpItem(
    icon: Icons.payments_rounded,
    title: 'Record payments',
    subtitle: 'Track order status, log payments, and see outstanding dues.',
  ),
  Divider(),
  _HelpItem(
    icon: Icons.receipt_long_rounded,
    title: 'Share invoices',
    subtitle: 'Generate branded invoice PDFs and send them to customers.',
  ),
  Divider(),
  _HelpItem(
    icon: Icons.notifications_active_rounded,
    title: 'Never miss a follow-up',
    subtitle: 'Smart reminders keep warm leads from going cold.',
  ),
]
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/shared/components/help_support_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/components/help_and_support_screen.dart test/shared/components/help_support_screen_test.dart
git commit -m "feat(help): rewrite Help content to match real Closr workflow + tokenize"
```

---

## Task 11: Business hub wording + full gate

**Files:**
- Modify: `lib/features/business/presentation/business_hub_screen.dart`
- Test: `test/features/business/business_hub_screen_test.dart` (verify still green)

- [ ] **Step 1: Fix tile subtitles for the new IA**

In `business_hub_screen.dart` change:
- `'Business Profile', 'Name, UPI, GST, invoice settings'` → `'Business Profile', 'Name, contact, payment, GST'`
- `'Settings', 'Profile, invoices, privacy'` → `'Settings', 'Notifications, invoices, support'`

(Keep the existing `Invoices` tile as the invoice *list*; Invoice Settings lives only in Settings.)

- [ ] **Step 2: Run the hub test**

Run: `flutter test test/features/business/business_hub_screen_test.dart`
Expected: PASS (if it asserts old subtitle text, update the assertion to the new copy).

- [ ] **Step 3: Full analyze + full test suite**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: All green.

- [ ] **Step 4: Commit**

```bash
git add lib/features/business/presentation/business_hub_screen.dart test/features/business/business_hub_screen_test.dart
git commit -m "refactor(business): align hub tile copy with consolidated IA"
```

---

## Self-Review (author)

**Spec coverage:**
- §1 Remove duplicates → Tasks 5,6,7,8,10,11 (kill inline sheets, dedupe logout/help, single Invoice Settings). ✅
- §2 Business Profile expansion → Tasks 1,2,8. ✅
- §3 Settings sections → Task 7. ✅
- §4 Remove from Profile → Task 8 (no logout/help/terms/about in Profile). ✅
- §5 Invoice Settings dedicated → Task 9. ✅
- §6 Logout flow (confirm, clear session, clear cache, return to login) → Tasks 5,6. ✅
- Help content refresh (added request) → Task 10. ✅
- Design-system consistency on touched screens → Tasks 4,7,8,9,10. ✅

**Deferred (Phase 2, per spec):** app-wide audit of untouched screens; theme/permissions/security/FAQs functionality.

**Placeholder scan:** No TBD/TODO; every code step has full source. ✅

**Type consistency:** `BusinessProfile.copyWith` covers every field the screens set; `updateInvoiceNumbering(prefix,nextNumber)`, `assetStoragePath(userId,kind,extension)`, `pickAndUpload(kind:)`, `confirmAndLogout(context,ref)`, `rootDestinationFor(authed:,profile:)`, `RootDestination`, `ProfileAnchor`, `InvoiceSettingsPreview` all defined before use. ✅

**Ordering note:** Task 7 (Settings) compiles only after Tasks 8–9; its test is deferred to Task 9 Step 6. Flagged inline.
