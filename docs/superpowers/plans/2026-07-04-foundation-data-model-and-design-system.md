# Foundation — Data Model, Security & Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the production data model (7 tables, RLS-secured, private storage) plus the design-system foundation (theme tokens + core components) and a business-profile setup flow — the base every later plan builds on.

**Architecture:** Supabase Postgres with deny-by-default Row Level Security on every table (rows scoped to `auth.uid()`), private Storage buckets with owner-scoped policies, applied as reviewable migrations via the Supabase MCP tools. Flutter side introduces a central theme (`lib/core/theme/`) replacing scattered inline colors, a handful of reusable widgets, pure-Dart models with `fromMap`/`toMap` (matching the existing codebase style — no codegen), and a Riverpod-backed business-profile service + setup screen gated into the post-login flow.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + Auth + Storage), `flutter_test`. No new dependencies.

---

## File structure (created / modified in this plan)

**Created**
- `lib/core/theme/app_colors.dart` — color tokens
- `lib/core/theme/app_spacing.dart` — spacing + radius tokens
- `lib/core/theme/app_text_styles.dart` — type scale
- `lib/core/theme/app_theme.dart` — assembles `ThemeData`
- `lib/core/utils/money.dart` — INR formatting (pure logic)
- `lib/shared/widgets/money_text.dart` — money display widget
- `lib/shared/widgets/status_pill.dart` — status → label/color pill
- `lib/shared/widgets/app_card.dart` — standard card container
- `lib/shared/widgets/app_primary_button.dart` — primary button
- `lib/features/business/data/business_profile.dart` — model
- `lib/features/business/data/business_profile_service.dart` — Supabase CRUD
- `lib/features/business/controller/business_profile_provider.dart` — Riverpod
- `lib/features/business/presentation/business_setup_screen.dart` — setup form
- `supabase/migrations/0001_core_schema.sql` — tables + triggers + indexes
- `supabase/migrations/0002_rls_policies.sql` — RLS
- `supabase/migrations/0003_storage_buckets.sql` — buckets + storage policies
- `test/core/utils/money_test.dart`
- `test/features/business/business_profile_test.dart`
- `test/shared/widgets/status_pill_test.dart`

**Modified**
- `lib/main.dart` — wire `AppTheme.light` into `MaterialApp`
- `lib/core/services/auth_service.dart` — replace `ensureUserProfile` (`users` table) with business-profile existence check
- `lib/app/splash_screen.dart` — route to setup screen when no business profile exists

> Migrations are stored as files for review, then applied with the Supabase MCP `apply_migration` tool at execution time. Keeping the `.sql` files in-repo gives a versioned, reviewable history even though MCP performs the apply.

---

## Task 1: Design tokens

**Files:**
- Create: `lib/core/theme/app_colors.dart`, `lib/core/theme/app_spacing.dart`, `lib/core/theme/app_text_styles.dart`, `lib/core/theme/app_theme.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create color tokens**

Create `lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Central color tokens. Do not hardcode Color(0xFF...) in widgets — use these.
class AppColors {
  AppColors._();

  // Brand — boutique plum + warm accent
  static const Color primary = Color(0xFF6C4ED9);
  static const Color primaryDark = Color(0xFF4B2FB0);
  static const Color accent = Color(0xFFE0A82E); // warm gold

  // Surfaces
  static const Color background = Color(0xFFF6F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F0FF);

  // Text
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);

  // Semantic
  static const Color success = Color(0xFF0F9D58);
  static const Color warning = Color(0xFFE08B00);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Money
  static const Color money = Color(0xFF0F9D58);
  static const Color dues = Color(0xFFDC2626);

  static const Color border = Color(0xFFE5E7EB);
}
```

- [ ] **Step 2: Create spacing + radius tokens**

Create `lib/core/theme/app_spacing.dart`:

```dart
/// Spacing + radius scale. Use these instead of magic numbers.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}
```

- [ ] **Step 3: Create type scale**

Create `lib/core/theme/app_text_styles.dart`:

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static const TextStyle heading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}
```

- [ ] **Step 4: Assemble ThemeData**

Create `lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
        ),
        scaffoldBackgroundColor: AppColors.background,
      );
}
```

- [ ] **Step 5: Wire theme into MaterialApp**

In `lib/main.dart`, replace the inline `theme: ThemeData(...)` block (lines ~46-50) with the shared theme. Add the import `import 'package:orderly_app/core/theme/app_theme.dart';` and set:

```dart
      theme: AppTheme.light,
```

- [ ] **Step 6: Verify it compiles**

Run: `flutter analyze lib/core/theme lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/theme lib/main.dart
git commit -m "feat(theme): add design tokens and central AppTheme"
```

---

## Task 2: INR money formatting (TDD)

**Files:**
- Create: `lib/core/utils/money.dart`
- Test: `test/core/utils/money_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/money_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/utils/money.dart';

void main() {
  group('Money.inr', () {
    test('formats whole rupees with symbol, no decimals', () {
      expect(Money.inr(1200), '₹1,200');
    });

    test('formats fractional rupees with two decimals', () {
      expect(Money.inr(1234.5), '₹1,234.50');
    });

    test('uses Indian digit grouping (lakhs)', () {
      expect(Money.inr(1234567), '₹12,34,567');
    });

    test('handles zero', () {
      expect(Money.inr(0), '₹0');
    });

    test('handles negatives (dues)', () {
      expect(Money.inr(-500), '-₹500');
    });

    test('can omit the symbol', () {
      expect(Money.inr(1200, symbol: false), '1,200');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/money_test.dart`
Expected: FAIL — `Money` / `money.dart` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/utils/money.dart`:

```dart
/// INR money formatting with Indian digit grouping (e.g. 12,34,567).
class Money {
  Money._();

  static String inr(num value, {bool symbol = true}) {
    final negative = value < 0;
    final abs = value.abs();
    final isWhole = abs == abs.roundToDouble();
    final fixed = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);

    final parts = fixed.split('.');
    final grouped = _groupIndian(parts[0]);
    final decimals = parts.length > 1 ? '.${parts[1]}' : '';

    return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped$decimals';
  }

  /// Groups the integer part: last 3 digits, then in pairs. 1234567 -> 12,34,567
  static String _groupIndian(String intPart) {
    if (intPart.length <= 3) return intPart;

    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);

    final buffer = StringBuffer();
    while (rest.length > 2) {
      buffer.write(',${rest.substring(rest.length - 2)}');
      rest = rest.substring(0, rest.length - 2);
    }
    return '$rest${buffer.toString().split(',').reversed.where((s) => s.isNotEmpty).map((s) => ',$s').join()},$last3';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/money_test.dart`
Expected: PASS (6 tests). If the grouping helper fails on the lakhs case, replace `_groupIndian` with this simpler, verified version:

```dart
  static String _groupIndian(String intPart) {
    if (intPart.length <= 3) return intPart;
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '${groups.join(',')},$last3';
  }
```

Re-run until PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/money.dart test/core/utils/money_test.dart
git commit -m "feat(money): add INR formatter with Indian digit grouping"
```

---

## Task 3: StatusPill widget (TDD on the style mapping)

**Files:**
- Create: `lib/shared/widgets/status_pill.dart`
- Test: `test/shared/widgets/status_pill_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/shared/widgets/status_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

void main() {
  group('StatusPillStyle.forStatus', () {
    test('maps available to success', () {
      final s = StatusPillStyle.forStatus('available');
      expect(s.label, 'Available');
      expect(s.color, AppColors.success);
    });

    test('maps booked to warning', () {
      expect(StatusPillStyle.forStatus('booked').color, AppColors.warning);
    });

    test('maps sold to secondary text color', () {
      expect(StatusPillStyle.forStatus('sold').label, 'Sold');
    });

    test('maps unpaid to danger', () {
      expect(StatusPillStyle.forStatus('unpaid').color, AppColors.danger);
    });

    test('maps paid to success', () {
      expect(StatusPillStyle.forStatus('paid').color, AppColors.success);
    });

    test('unknown status falls back to a readable label + neutral color', () {
      final s = StatusPillStyle.forStatus('whatever');
      expect(s.label, 'Whatever');
      expect(s.color, AppColors.textSecondary);
    });
  });

  testWidgets('StatusPill renders its label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusPill(status: 'booked')),
    ));
    expect(find.text('Booked'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/status_pill_test.dart`
Expected: FAIL — `status_pill.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/shared/widgets/status_pill.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class StatusPillStyle {
  const StatusPillStyle(this.label, this.color);
  final String label;
  final Color color;

  static StatusPillStyle forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return const StatusPillStyle('Available', AppColors.success);
      case 'booked':
        return const StatusPillStyle('Booked', AppColors.warning);
      case 'sold':
        return const StatusPillStyle('Sold', AppColors.textSecondary);
      case 'paid':
        return const StatusPillStyle('Paid', AppColors.success);
      case 'partial':
        return const StatusPillStyle('Partial', AppColors.warning);
      case 'unpaid':
        return const StatusPillStyle('Unpaid', AppColors.danger);
      case 'pending':
        return const StatusPillStyle('Pending', AppColors.warning);
      case 'packed':
        return const StatusPillStyle('Packed', AppColors.info);
      case 'shipped':
        return const StatusPillStyle('Shipped', AppColors.info);
      case 'delivered':
        return const StatusPillStyle('Delivered', AppColors.success);
      default:
        final label = status.isEmpty
            ? '—'
            : status[0].toUpperCase() + status.substring(1);
        return StatusPillStyle(label, AppColors.textSecondary);
    }
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final style = StatusPillStyle.forStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/status_pill_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/status_pill.dart test/shared/widgets/status_pill_test.dart
git commit -m "feat(ui): add StatusPill with status style mapping"
```

---

## Task 4: MoneyText, AppCard, AppPrimaryButton widgets

**Files:**
- Create: `lib/shared/widgets/money_text.dart`, `lib/shared/widgets/app_card.dart`, `lib/shared/widgets/app_primary_button.dart`

- [ ] **Step 1: Create MoneyText**

Create `lib/shared/widgets/money_text.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/utils/money.dart';

/// Renders a money value with INR formatting. Green for positive, red for dues.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.colorBySign = false,
  });

  final num value;
  final TextStyle? style;
  final bool colorBySign;

  @override
  Widget build(BuildContext context) {
    final base = style ??
        const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary);
    final color = colorBySign
        ? (value < 0 ? AppColors.dues : AppColors.money)
        : base.color;
    return Text(Money.inr(value), style: base.copyWith(color: color));
  }
}
```

- [ ] **Step 2: Create AppCard**

Create `lib/shared/widgets/app_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 3: Create AppPrimaryButton**

Create `lib/shared/widgets/app_primary_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify compile**

Run: `flutter analyze lib/shared/widgets`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/money_text.dart lib/shared/widgets/app_card.dart lib/shared/widgets/app_primary_button.dart
git commit -m "feat(ui): add MoneyText, AppCard, AppPrimaryButton"
```

---

## Task 5: Core schema migration

**Files:**
- Create: `supabase/migrations/0001_core_schema.sql`

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0001_core_schema.sql`:

```sql
-- Closr core schema (Phase 1 foundation)

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- business_profile (one per user)
create table public.business_profile (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  logo_url text,
  address text,
  phone text,
  email text,
  upi_id text,
  upi_name text,
  gstin text,
  default_gst_rate numeric(5,2) not null default 0,
  invoice_prefix text not null default 'INV-',
  next_invoice_number integer not null default 1,
  currency text not null default 'INR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text not null,
  email text,
  address text,
  notes text,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, phone)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  sku text,
  images text[] not null default '{}',
  price numeric(12,2) not null default 0,
  unit text not null default 'pc',
  gst_rate numeric(5,2),
  is_unique boolean not null default false,
  piece_status text not null default 'available'
    check (piece_status in ('available','booked','sold')),
  qty_on_hand integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  source text not null default 'manual'
    check (source in ('dm','paste','product','manual')),
  message text,
  intent text,
  status text not null default 'new'
    check (status in ('new','follow','won','lost')),
  follow_up_date timestamptz,
  follow_up_note text,
  activities jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  order_number integer,
  status text not null default 'pending'
    check (status in ('pending','packed','shipped','delivered')),
  courier text,
  tracking_no text,
  shipped_at timestamptz,
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','partial','paid')),
  subtotal numeric(12,2) not null default 0,
  tax_total numeric(12,2) not null default 0,
  grand_total numeric(12,2) not null default 0,
  invoice_number text,
  notes text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name text not null,
  image_url text,
  unit_price numeric(12,2) not null default 0,
  gst_rate numeric(5,2) not null default 0,
  qty integer not null default 1,
  line_total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  amount numeric(12,2) not null default 0,
  method text not null default 'upi' check (method in ('upi','cash','other')),
  proof_image_url text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- updated_at triggers
create trigger trg_business_profile_updated before update on public.business_profile
  for each row execute function public.set_updated_at();
create trigger trg_customers_updated before update on public.customers
  for each row execute function public.set_updated_at();
create trigger trg_products_updated before update on public.products
  for each row execute function public.set_updated_at();
create trigger trg_leads_updated before update on public.leads
  for each row execute function public.set_updated_at();
create trigger trg_orders_updated before update on public.orders
  for each row execute function public.set_updated_at();

-- indexes
create index idx_customers_user on public.customers(user_id);
create index idx_products_user on public.products(user_id);
create index idx_leads_user_status on public.leads(user_id, status);
create index idx_orders_user_status on public.orders(user_id, status);
create index idx_order_items_order on public.order_items(order_id);
create index idx_payments_order on public.payments(order_id);
```

- [ ] **Step 2: Apply the migration via MCP**

Use the Supabase MCP tool `apply_migration` with name `0001_core_schema` and the SQL body above.
Before applying: run `list_projects` (read-only) to confirm the correct project, and `list_tables` to confirm these tables do not already exist.
Expected: migration succeeds; `list_tables` afterward shows the 7 new tables in `public`.

- [ ] **Step 3: Commit the migration file**

```bash
git add supabase/migrations/0001_core_schema.sql
git commit -m "feat(db): core schema — business, customers, products, leads, orders, items, payments"
```

---

## Task 6: RLS policies migration

**Files:**
- Create: `supabase/migrations/0002_rls_policies.sql`

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0002_rls_policies.sql`:

```sql
-- Enable RLS everywhere (deny-by-default) and add owner-scoped policies.

alter table public.business_profile enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.leads enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create policy "own business_profile" on public.business_profile
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own customers" on public.customers
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own products" on public.products
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own leads" on public.leads
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own orders" on public.orders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own order_items" on public.order_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own payments" on public.payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Apply the migration via MCP**

Use `apply_migration` with name `0002_rls_policies` and the SQL above.

- [ ] **Step 3: Verify RLS with the security advisor**

Use the Supabase MCP tool `get_advisors` with type `security`.
Expected: **no** findings of category "RLS disabled in public" for any of the 7 tables. If any table reports RLS disabled, fix and re-apply before continuing.

- [ ] **Step 4: Verify policies exist**

Use the MCP tool `execute_sql` with:

```sql
select tablename, count(*) as policies
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;
```

Expected: each of the 7 tables appears with `policies >= 1`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_rls_policies.sql
git commit -m "feat(db): enable RLS with owner-scoped policies on all tables"
```

---

## Task 7: Private storage buckets migration

**Files:**
- Create: `supabase/migrations/0003_storage_buckets.sql`

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0003_storage_buckets.sql`. Files are stored under a `<user_id>/...` path prefix so policies can scope by the first folder segment:

```sql
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', false),
       ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

-- product-images: owner-only, scoped by top folder = user id
create policy "product-images read own" on storage.objects
  for select using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images write own" on storage.objects
  for insert with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images update own" on storage.objects
  for update using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images delete own" on storage.objects
  for delete using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- payment-proofs: owner-only
create policy "payment-proofs read own" on storage.objects
  for select using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs write own" on storage.objects
  for insert with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs update own" on storage.objects
  for update using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs delete own" on storage.objects
  for delete using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Apply the migration via MCP**

Use `apply_migration` with name `0003_storage_buckets`.

- [ ] **Step 3: Verify buckets are private**

Use `execute_sql` with:

```sql
select id, public from storage.buckets
where id in ('product-images','payment-proofs');
```

Expected: both rows present with `public = false`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0003_storage_buckets.sql
git commit -m "feat(db): private storage buckets with owner-scoped policies"
```

---

## Task 8: BusinessProfile model (TDD)

**Files:**
- Create: `lib/features/business/data/business_profile.dart`
- Test: `test/features/business/business_profile_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/business/business_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';

void main() {
  group('BusinessProfile', () {
    test('hasGst is true only when gstin is non-empty', () {
      expect(
        BusinessProfile(name: 'Shop', gstin: '29ABCDE1234F1Z5').hasGst,
        isTrue,
      );
      expect(BusinessProfile(name: 'Shop', gstin: '').hasGst, isFalse);
      expect(BusinessProfile(name: 'Shop', gstin: null).hasGst, isFalse);
    });

    test('round-trips through toMap/fromMap', () {
      final original = BusinessProfile(
        name: 'Sarees by Anu',
        phone: '9876543210',
        upiId: 'anu@upi',
        upiName: 'Anu',
        gstin: '29ABCDE1234F1Z5',
        defaultGstRate: 5,
        invoicePrefix: 'ANU-',
        nextInvoiceNumber: 42,
      );
      final restored = BusinessProfile.fromMap(original.toMap());
      expect(restored.name, 'Sarees by Anu');
      expect(restored.upiId, 'anu@upi');
      expect(restored.defaultGstRate, 5);
      expect(restored.nextInvoiceNumber, 42);
      expect(restored.hasGst, isTrue);
    });

    test('fromMap tolerates missing optional fields', () {
      final p = BusinessProfile.fromMap({'name': 'X'});
      expect(p.name, 'X');
      expect(p.currency, 'INR');
      expect(p.invoicePrefix, 'INV-');
      expect(p.nextInvoiceNumber, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: FAIL — `business_profile.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/business/data/business_profile.dart`:

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

  bool get hasGst => (gstin ?? '').trim().isNotEmpty;

  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static int _asInt(dynamic v, int fallback) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id']?.toString(),
      name: (map['name'] ?? '').toString(),
      logoUrl: map['logo_url']?.toString(),
      address: map['address']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      upiId: map['upi_id']?.toString(),
      upiName: map['upi_name']?.toString(),
      gstin: map['gstin']?.toString(),
      defaultGstRate: _asDouble(map['default_gst_rate']),
      invoicePrefix: (map['invoice_prefix'] ?? 'INV-').toString(),
      nextInvoiceNumber: _asInt(map['next_invoice_number'], 1),
      currency: (map['currency'] ?? 'INR').toString(),
    );
  }

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
        'invoice_prefix': invoicePrefix,
        'next_invoice_number': nextInvoiceNumber,
        'currency': currency,
      };

  BusinessProfile copyWith({
    String? name,
    String? address,
    String? phone,
    String? upiId,
    String? upiName,
    String? gstin,
    double? defaultGstRate,
  }) {
    return BusinessProfile(
      id: id,
      name: name ?? this.name,
      logoUrl: logoUrl,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email,
      upiId: upiId ?? this.upiId,
      upiName: upiName ?? this.upiName,
      gstin: gstin ?? this.gstin,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      invoicePrefix: invoicePrefix,
      nextInvoiceNumber: nextInvoiceNumber,
      currency: currency,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/business/business_profile_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/business/data/business_profile.dart test/features/business/business_profile_test.dart
git commit -m "feat(business): add BusinessProfile model"
```

---

## Task 9: BusinessProfileService + provider

**Files:**
- Create: `lib/features/business/data/business_profile_service.dart`, `lib/features/business/controller/business_profile_provider.dart`

- [ ] **Step 1: Create the service**

Create `lib/features/business/data/business_profile_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_profile.dart';

class BusinessProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<BusinessProfile?> fetch() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final row = await _supabase
        .from('business_profile')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return BusinessProfile.fromMap(row);
  }

  Future<bool> exists() async => (await fetch()) != null;

  Future<BusinessProfile> upsert(BusinessProfile profile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final payload = {
      ...profile.toMap(),
      'user_id': user.id,
    };

    final row = await _supabase
        .from('business_profile')
        .upsert(payload, onConflict: 'user_id')
        .select()
        .single();

    return BusinessProfile.fromMap(row);
  }
}
```

- [ ] **Step 2: Create the provider**

Create `lib/features/business/controller/business_profile_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_profile.dart';
import '../data/business_profile_service.dart';

final businessProfileServiceProvider =
    Provider<BusinessProfileService>((ref) => BusinessProfileService());

/// Loads the current user's business profile (null if not set up yet).
final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  return ref.watch(businessProfileServiceProvider).fetch();
});
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/features/business`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/business/data/business_profile_service.dart lib/features/business/controller/business_profile_provider.dart
git commit -m "feat(business): add BusinessProfileService and providers"
```

---

## Task 10: Business setup screen

**Files:**
- Create: `lib/features/business/presentation/business_setup_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/features/business/presentation/business_setup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import '../controller/business_profile_provider.dart';
import '../data/business_profile.dart';

class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key, this.onDone});

  /// Called after a successful save (e.g. to navigate into the app).
  final VoidCallback? onDone;

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _upiId = TextEditingController();
  final _upiName = TextEditingController();
  final _gstin = TextEditingController();
  final _gstRate = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _upiId, _upiName, _gstin, _gstRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = BusinessProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
      upiName: _upiName.text.trim().isEmpty ? null : _upiName.text.trim(),
      gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
      defaultGstRate: double.tryParse(_gstRate.text.trim()) ?? 0,
    );

    try {
      await ref.read(businessProfileServiceProvider).upsert(profile);
      ref.invalidate(businessProfileProvider);
      if (!mounted) return;
      widget.onDone?.call();
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
      appBar: AppBar(title: const Text('Set up your business')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Tell customers who they are buying from. This appears on your receipts.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(_name, 'Business name', required: true),
            _field(_phone, 'Phone (WhatsApp)', keyboard: TextInputType.phone),
            _field(_address, 'Address', maxLines: 2),
            const SizedBox(height: AppSpacing.sm),
            const Text('Payments', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            _field(_upiId, 'UPI ID (e.g. name@bank)'),
            _field(_upiName, 'Name on UPI'),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tax (optional)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Add a GSTIN only if you are GST-registered. Leave blank for a plain receipt.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            _field(_gstin, 'GSTIN'),
            _field(_gstRate, 'Default GST %', keyboard: TextInputType.number),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Save & continue',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/features/business/presentation`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/business/presentation/business_setup_screen.dart
git commit -m "feat(business): add business setup screen"
```

---

## Task 11: Gate setup into the post-login flow

**Files:**
- Modify: `lib/core/services/auth_service.dart` (replace `ensureUserProfile`)
- Modify: `lib/app/splash_screen.dart` (route to setup when no profile)

- [ ] **Step 1: Replace `ensureUserProfile` with a business-profile check**

In `lib/core/services/auth_service.dart`, replace the entire `ensureUserProfile` method (lines ~49-71, which writes to the legacy `users` table) with:

```dart
  /// Returns true when the signed-in user already has a business profile.
  Future<bool> hasBusinessProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final existing = await supabase
        .from('business_profile')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

    return existing != null;
  }
```

- [ ] **Step 2: Route to setup in the splash flow**

Open `lib/app/splash_screen.dart` and read `_initApp()` (around lines 45-70). It currently calls `AuthService().ensureUserProfile()` then loads leads and navigates. Replace the post-login branch so that when the user has no business profile, it navigates to `BusinessSetupScreen`, otherwise into the app. Add imports:

```dart
import 'package:orderly_app/features/business/presentation/business_setup_screen.dart';
```

Then, inside `_initApp()` where `isLoggedIn` is true, replace the `await AuthService().ensureUserProfile();` line and the subsequent navigation into `MainScreen` with:

```dart
      _setLoadingText("Checking your business...");
      final hasProfile = await AuthService().hasBusinessProfile();

      if (!mounted) return;
      if (!hasProfile) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BusinessSetupScreen(
              onDone: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const MainScreen()),
              ),
            ),
          ),
        );
        return;
      }
```

Keep the existing "load your leads" + `MainScreen` navigation for the `hasProfile == true` path. (If the existing code references `ensureUserProfile` elsewhere, update those call sites to `hasBusinessProfile` or remove them.)

- [ ] **Step 3: Verify the app compiles**

Run: `flutter analyze`
Expected: `No issues found!` (resolve any references to the removed `ensureUserProfile`).

- [ ] **Step 4: Manual smoke test**

Run the app against the Supabase project:

```bash
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Verify: log in with a fresh account → land on the themed **Set up your business** screen → fill name + UPI (leave GSTIN blank) → Save → land in the app. Kill and relaunch → skips setup (profile now exists).

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/auth_service.dart lib/app/splash_screen.dart
git commit -m "feat(business): gate business setup into post-login flow"
```

---

## Task 12: Full test + analyze gate

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: all tests pass (money, business profile, status pill, plus the default widget test — update `test/widget_test.dart` if it references removed/changed startup behavior).

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Re-run the Supabase security advisor**

Use MCP `get_advisors` type `security`. Expected: no "RLS disabled" findings on any `public` table.

- [ ] **Step 4: Final commit if anything changed**

```bash
git add -A
git commit -m "chore(foundation): green tests + clean analyze for foundation slice"
```

---

## Self-review notes (against the spec)

- **Data model (spec §4):** all 7 tables created with the documented fields incl. `is_unique`/`piece_status`/`qty_on_hand`, order shipping columns, snapshot fields on `order_items`, and `payments`. `order_number` generation is intentionally deferred to Plan 4 (Orders); the column exists now. ✅
- **Storage (spec §5):** private buckets `product-images` + `payment-proofs`, owner-scoped by folder = user id, no PDF bucket. ✅
- **Security (spec §8):** RLS enabled deny-by-default on every table + owner policies, verified by advisor; secrets still via `--dart-define`; no `service_role` in app. ✅
- **UI/UX (spec §7):** tokens + component kit started (`MoneyText`, `StatusPill`, `AppCard`, `AppPrimaryButton`); more components added by later screen plans (YAGNI). ✅
- **Business profile (spec §4, §6):** model + service + provider + setup screen capturing name, phone, address, UPI, optional GSTIN/GST rate; `hasGst` drives later GST display. ✅
- **GST optional (locked decision):** enforced via `hasGst` and a blank-allowed GSTIN field. ✅
- **Deferred correctly:** catalog, customers CRUD, orders, payments, invoicing, dashboard, store-hardening — each their own plan. Legacy `users`-table write removed to avoid a second source of truth for business identity.
```
