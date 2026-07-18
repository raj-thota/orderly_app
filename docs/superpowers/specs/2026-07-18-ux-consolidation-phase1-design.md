# UX Consolidation — Phase 1 Design

Date: 2026-07-18
Status: Approved (design), pending implementation plan
Scope: Phase 1 only — sections 1–6 of the UX-audit request (dedup, Settings
reorg, Business Profile expansion, dedicated Invoice Settings, logout/nav fix,
Help & Support content refresh). The app-wide audit (request sections 7–8
across all ~20 screens) is a deliberately deferred follow-up phase.

## Goal

Remove duplicate features, give every feature exactly one home, and make the
Profile / Settings / Invoice-Settings surface feel like a polished commercial
product (Linear/Stripe/Apple bar) rather than a prototype. Fix the broken
logout. Ground all touched screens in the existing design-system tokens.

## Decisions locked (from brainstorming)

- **Phasing:** Phase 1 now (sections 1–6 + nav/logout). Audit (7–8) deferred.
- **Persistence:** real SQL migration — this repo delivers the migration file;
  the user applies it to their separate Supabase project (`dgviploqkwyuttcdnddq`;
  not the MCP-connected project — never migrate there). Model reads are
  null-tolerant so the app keeps working before the migration is applied.
- **Design-system depth:** tokenize only Phase-1-touched screens + shared
  nav/header/settings components. Do not sweep untouched screens.
- **Invoice config owner:** dedicated **Invoice Settings** screen only. Profile
  links to it; does not duplicate invoice fields.
- **Payment vs Preferences:** Payment (UPI/bank/QR) lives in **Profile**;
  Preferences (language/timezone/notifications) live in **Settings**.
- **IA:** Business hub keeps distinct **Business Profile** + **Settings** tiles;
  Today avatar → Profile stays. No new bottom-nav tab.

## A. Information architecture — one home per concern

| Concern | Single owner |
|---|---|
| Business identity: name, owner, contact, address, GST/PAN, logo, payment (UPI/bank/QR) | **Business Profile** |
| Invoice config: prefix, numbering, tax, currency, terms, footer, logo, signature, preview | **Invoice Settings** (dedicated, new) |
| App config: notifications, language, theme-soon; legal; support; about; logout | **Settings** |

Cross-links (deep-link, never duplicate):
- Settings → Business → **Payment Settings** opens Profile's Payment section.
- Settings → Business → **Tax & GST** opens Invoice Settings.
- Profile footer tile → Invoice Settings.

## B. Data model + migration

Current `business_profile` columns: `name, logo_url, address, phone, email,
upi_id, upi_name, gstin, default_gst_rate, invoice_prefix, next_invoice_number,
currency, invoice_template`.

New columns (one migration file under `supabase/`, user applies):

```
owner_name           text
city                 text
state                text
pincode              text
pan                  text
business_type        text
bank_account_name    text
bank_account_number  text
bank_ifsc            text
default_payment_method text        -- 'upi' | 'bank' | 'cash'
gst_enabled          boolean default false
payment_terms        text
invoice_footer       text
signature_url        text
language             text default 'en'
timezone             text default 'Asia/Kolkata'
```

- Extend `BusinessProfile` model: fields + `fromMap` + `toMap` + `copyWith` for
  all of the above. All new fields null-tolerant so pre-migration reads (missing
  columns) do not throw.
- **QR preview:** rendered live from `upi_id` with `qr_flutter`. No column.
- **Logo / signature upload:** `image_picker` + `flutter_image_compress` →
  Supabase Storage bucket `business-assets` (public read, per-user path). Store
  resulting URL in `logo_url` / `signature_url`. Migration/setup note documents
  the bucket + policy; app fails gracefully if bucket absent.
- **Notification prefs:** reuse the existing `NotificationsScreen`. No new
  columns. Settings → General → Notifications links to it.
- Converge Profile writes off the raw `userProfileProvider` mutation onto the
  typed `BusinessProfileService.upsert`. `userProfileProvider` stays for the
  read/header (it merges auth metadata) but is invalidated after saves.

## C. Screens

### Business Profile (`features/profile/presentation/profile_screen.dart`, rewritten)

Grouped premium cards, shared field/section widgets, one Save path via
`BusinessProfileService.upsert`.

- **Header:** logo (tap to upload) + business name + email.
- **Business Information:** Business Name, Owner Name, Phone, Email, Address,
  City, State, Pincode.
- **Business Identity:** GST Number (optional), PAN (optional), Business Type,
  Business Logo.
- **Payment Details:** UPI ID, UPI Name, Bank Account (name/number/IFSC,
  optional), Default Payment Method, live UPI **QR preview**.
- **Footer tile:** "Invoice Settings" → Invoice Settings screen (link only).
- **States:** loading (skeleton/spinner), saving (inline), error (snackbar +
  retry), empty (hint text per field).
- **Removed from Profile:** Help & Support, Notifications tile, Logout button
  (all move to Settings).

### Invoice Settings (new `features/invoices/presentation/invoice_settings_screen.dart`)

- Invoice Prefix, Starting Invoice Number, GST toggle (`gst_enabled`), Default
  Tax (`default_gst_rate`), Currency, Payment Terms, Notes/Footer, Logo upload,
  Signature upload, **live invoice preview** (reuse existing `invoice_pdf` /
  share-preview components with sample data).
- Persists to `business_profile` via the typed service.

### Settings (`features/settings/presentation/settings_screen.dart`, rebuilt)

Reuses the real existing screens; deletes the weak inline `_showStatic` sheets.

- **General:** Notifications (→ `NotificationsScreen`), Language, Theme
  *(Coming soon, disabled)*.
- **Business:** Invoice Settings (→ new screen), Payment Settings (→ Profile
  payment section), Tax & GST (→ Invoice Settings).
- **Security:** Data Privacy (→ `PrivacyPolicyScreen`), Permissions *(soon)*,
  Security *(soon)*.
- **Support:** Help Center (→ `HelpSupportScreen`), Contact Support (mailto),
  Report a Bug (mailto, prefilled subject), Request a Feature (mailto), FAQs
  *(soon)*.
- **About:** App Version (real string, `1.0.0`), Terms (→ `TermsScreen`),
  Privacy Policy (→ `PrivacyPolicyScreen`), Open Source Licenses (Flutter
  built-in `showLicensePage`).
- **Account:** Logout (shared confirm-and-logout action).

Coming-soon tiles render disabled with a "Coming soon" trailing chip, not dead
buttons.

## D. Logout + reactive navigation (root-cause fix)

Root cause: no widget watches `authProvider`, so `logout()` resets state but
nothing re-routes — Settings "Sign Out" appears to do nothing; Profile "Logout"
worked only via a hand-rolled `pushAndRemoveUntil`.

- Introduce **`RootGate`** (ConsumerWidget) that watches
  `authProvider.isAuthenticated` and renders reactively:
  not authed → `AppIntroScreen`; authed & no business profile →
  `BusinessSetupScreen`; else → `MainScreen`.
- `SplashScreen` routes into `RootGate` instead of `pushReplacement`-ing
  `MainScreen` directly. Cold-start animation + `hasBusinessProfile` check
  preserved.
- Shared `confirmAndLogout(context, ref)`: confirmation dialog → `logout()` →
  `ref.invalidate` of business/data providers (userProfile, businessProfile,
  orders, enquiries) to clear cached business data → gate reactively returns to
  intro. Both former logout buttons collapse to this one action.

## E. Deletions / rewires (dedup)

- Delete Settings' inline `_showStatic` Help & Data-Privacy bottom sheets.
- Remove Profile's Notifications / Help / Logout entries.
- Settings no longer opens `InvoicesScreen` for "Invoice Settings"; it opens the
  dedicated Invoice Settings screen.
- Business hub wording: keep "Invoices" (the list) distinct from "Invoice
  Settings" (config, inside Settings). Update tile subtitles that over-promise.
- Profile writes converge onto the typed service (remove raw Supabase mutation).

## F. Help & Support content refresh

Current Help copy describes a generic "leads / follow-ups" app. Rewrite Quick
Help to match what Closr actually does, in the user's real workflow order:

1. **Capture** — paste a WhatsApp message or use voice to log an enquiry/order.
2. **Today** — your daily pipeline of orders + enquiries in one place.
3. **Focus / My Work** — Start My Work to work items one at a time.
4. **Orders & Payments** — track order status, record payments, see dues.
5. **Invoices** — generate branded invoices/PDFs and share them.
6. **Follow-ups & reminders** — smart reminders so no deal goes cold.
7. **Catalog** — your products/pieces for fast order entry.
8. **Closr AI & Go Pro** — AI assistant; Pro unlocks AI capture, broadcasts,
   branded invoices.

Keep Contact Support (mailto `closrsupport@gmail.com`), Privacy Policy, Terms,
version footer. Tokenize the screen (drop `Colors.deepPurple`, magic radii) to
match the design system.

## G. Design-system consistency (touched screens only)

- Use `AppColors` / `AppSpacing` / `AppRadius` / `AppTextStyles` throughout;
  remove `Colors.deepPurple`, `Colors.grey.shade50`, magic `16`/`18`.
- Shared reusable widgets so all three screens match:
  - `SettingsSection` (section header + card grouping)
  - `SettingsTile` (with `comingSoon` and `danger` variants, uniform chevron)
  - `ProfileFieldRow` (label + value/edit, one interaction model)
  - `AppScreenHeader` (consistent title/back across the three screens)
- Uniform card radius (`AppRadius.md`), border color, icon sizes, section
  header typography.

## H. Testing

- Settings renders all six sections; coming-soon tiles disabled; each tile
  routes to the correct screen/action.
- `confirmAndLogout` shows dialog; confirm calls `logout()` + invalidates
  providers; cancel is a no-op.
- `RootGate` renders MainScreen when authed+profile, Intro when not authed,
  BusinessSetup when authed+no-profile.
- Profile save calls `BusinessProfileService.upsert` with edited fields; shows
  saving/error states; QR preview renders from `upi_id`.
- Invoice Settings persists fields and renders the live preview.
- Gate: `flutter analyze` clean + `flutter test` green before done.

## Recommended approach vs alternative

- **Recommended (this spec):** reactive `RootGate` + typed-service convergence —
  fixes logout at the root and removes the imperative-nav duplication.
- **Lighter alternative:** keep imperative nav, route both logout buttons through
  a shared `pushAndRemoveUntil` helper. Less churn but leaves the root-level
  fragility that caused the bug. Rejected.

## Explicitly out of scope (Phase 2+)

- App-wide audit of Today / My Work / Orders / Capture / Payments / Leads /
  Followups / Catalog / Subscription / Conversations / Quotations.
- Full-app token sweep of untouched screens.
- Theme switching, Permissions, Security screens, FAQs content (shown as
  "Coming soon" now).
