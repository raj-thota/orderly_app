# Today Tab Redesign — Spec

**Date:** 2026-07-15  
**Branch:** spec/v1-tdd  
**Scope:** `lib/features/today/presentation/today_screen.dart` + `pubspec.yaml`

---

## Goal

Match the Today tab to the V1.0.0 mockup: richer glance card with icon tiles + robot mascot, carousel nudge with pagination dots, customer attention list with priority badges, and AI suggested actions horizontal scroll. All data from existing providers — no hardcoding, no new backend.

---

## Files Changed

| File | Change |
|---|---|
| `lib/features/today/presentation/today_screen.dart` | Full rebuild |
| `pubspec.yaml` | Add `- assets/robo.png` |

---

## Section 1 — AppBar

Replace current inline header with a proper `AppBar`:

- **Left**: `Icons.menu` hamburger — no-op (future drawer)
- **Center**: `RichText` sparkle (`Icons.auto_awesome`, size 16, `AppColors.primary`) + `"Closr"` bold 20px `AppColors.primary`
- **Right**: `Stack` — `Icons.notifications_outlined` + red `CircleAvatar` badge showing `workItemsProvider.pendingCount`; taps `Navigator.push` to `NotificationsScreen`
- `backgroundColor: AppColors.background`, `elevation: 0`

Badge count = pending AI work items. Same data as Section 5 → no new provider.

---

## Section 2 — Greeting

```
Good [morning/afternoon/evening], {business_name} 👋   bold 22px textPrimary
Here's what's happening with your business today.      13px textSecondary
```

Source: `userProfileProvider` (`business_name`), `DateTime.now()`.

---

## Section 3 — "Today at a glance" Card

`Container` with gradient (`briefGradientStart` → `briefGradientEnd`), `BorderRadius.circular(AppRadius.lg)`.

Internal layout — `Column`:
1. `"Today at a glance"` white 13px label
2. `Stack`:
   - `Row` of 4 `_StatTile` widgets (left ~65% width)
   - `Positioned` `robo.png` right side, height ~130px, overlapping card top
3. `"Start My Work →"` white `FilledButton`, `foregroundColor: AppColors.primary`, `onPressed: () => widget.onNavigate(1)`

### `_StatTile` widget

Parameters: `icon`, `label`, `value`, `badgeText`, `badgeColor`

Layout (vertical):
- Icon in `Container` 40×40, `borderRadius 10`, `Colors.white.withValues(alpha:0.15)` background
- Label: white 11px
- Value: white bold 16px
- Badge pill: `badgeText` in rounded container, 10px, colored background `badgeColor.withValues(alpha:0.25)`, text `badgeColor`

Badge derivation:

| Tile | Icon | Zero badge | Non-zero badge |
|---|---|---|---|
| Follow-ups due | `Icons.chat_bubble_outline` | "All caught up" green | "Needs attention" `AppColors.danger` |
| Orders today | `Icons.shopping_bag_outlined` | "No orders" gray | "New order" `AppColors.success` |
| Revenue today | `Icons.currency_rupee` | "No sales yet" `AppColors.warning` | `Money.inr(revenue)` `AppColors.success` |
| Outstanding | `Icons.layers_outlined` | "Total due" `AppColors.info` | "Total due" `AppColors.info` |

---

## Section 4 — Carousel Nudge

Build `List<_NudgeData>` dynamically from `brief`:
1. `brief.dueFollowUps > 0` → clock icon, "X follow-up(s) need your attention", "Review and take action", `onTap: () => widget.onNavigate(1)`
2. `brief.outstanding > 0` → rupee icon, "₹X outstanding payments", "Collect payments", `onTap: () => widget.onNavigate(2)` (Orders tab)
3. `brief.ordersToday > 0` → bag icon, "X new order(s) placed today", "View orders", `onTap: () => widget.onNavigate(2)`

If list is empty: skip section entirely.

`PageController _nudgePageController` in state. `PageView.builder` height 88px, white card, `BorderRadius.circular(AppRadius.md)`.

Dot indicator: `Row` of `AnimatedContainer` dots, active = `AppColors.primary` 8px wide, inactive = `AppColors.border` 6px wide.

---

## Section 5 — "Needs Your Attention"

Only render if `workState.items.isNotEmpty`.

Header row:
- `"Needs your attention"` bold 15px
- `"View all (${workState.pendingCount})"` `AppColors.primary` TextButton → `widget.onNavigate(1)`

Items: `workState.items.take(3)` (already sorted by score desc from service).

### `_AttentionTile` widget

Parameters: `AiWorkItem item`, `VoidCallback onTap`

Layout `InkWell` → `Row`:
- **Avatar** 44px circle: `AppColors.aiSurface` bg, initials from `item.customerName` (first letters of first + last word), `AppColors.primary` text
- **Middle** `Expanded`:
  - Row: name bold 14px + priority badge pill
  - `item.context ?? item.title` gray 12px, max 1 line
  - `_timeAgo(item.createdAt)` gray 11px
- **Right** `Column`:
  - `Money.inr(item.amount)` bold 14px (if amount != null)
  - Outlined action button 32px height: label from `_actionLabel(item.kind)`
- `Icons.chevron_right_rounded` gray

Priority badge colors: `high` → `AppColors.danger`, `medium` → `AppColors.warning`, `low` → `AppColors.success`. Background = color with 15% opacity, text = color.

Action label mapping:
```
payment_reminder | overdue_payment → "Send Reminder"
follow_up | call                   → "Follow Up"
*                                  → "Message"
```

All taps → `widget.onNavigate(1)`.

---

## Section 6 — AI Suggested Actions

Only render if `workState.items.isNotEmpty`.

Header row:
- `Icons.auto_awesome` 14px `AppColors.primary` + `" AI suggested actions"` bold 15px
- `"View all"` TextButton → `widget.onNavigate(1)`

`SingleChildScrollView(scrollDirection: Axis.horizontal)` of `_AiActionCard` widgets from `workState.items.take(3)`.

### `_AiActionCard` widget

Width 148px, white card, `BorderRadius.circular(AppRadius.md)`, shadow.

Layout `Column` (padding 12):
- Icon `Container` 40×40 rounded: icon + background color from kind
- Description text 12px bold, 2 lines max: `_actionDescription(item)`
- CTA `TextButton` 11px `AppColors.primary`: `_actionCta(item)` + `" →"`

Kind → icon/color/description/CTA:

| kind | icon | color | description | CTA |
|---|---|---|---|---|
| `payment_reminder` | `Icons.chat_rounded` | green `0xFF25D366` | "Send price to {name}" | "Send Now" |
| `follow_up` / `call` | `Icons.phone_outlined` | `AppColors.primary` | "Call follow-up for {name}" | "Call Now" |
| `share_catalog` / `offer` | `Icons.card_giftcard_outlined` | `AppColors.warning` | "Offer discount to {name}" | "Create Offer" |
| default | `Icons.message_outlined` | `AppColors.aiAccent` | "Message {name}" | "Message" |

All taps → `widget.onNavigate(1)`.

---

## pubspec.yaml Change

```yaml
assets:
  - assets/env/default.env
  - assets/icons/
  - assets/logo/
  - assets/robo.png        # ← add this line
```

---

## State

`_TodayScreenState` adds:
- `late PageController _nudgePageController`
- `int _nudgePage = 0`
- `initState`: init controller, add listener for `_nudgePage`
- `dispose`: dispose controller

---

## Helper Methods

- `_greeting(DateTime)` — existing, keep
- `_timeAgo(DateTime?)` — "X days ago" / "X hours ago" / "Today"
- `_actionLabel(String kind)` — kind → button label
- `_actionDescription(AiWorkItem)` — kind + name → card description
- `_actionCta(String kind)` — kind → CTA string
- `_initials(String? name)` — "Rekha Joshi" → "RJ"

---

## What Does NOT Change

- `TodayBrief` / `buildTodayBrief` — untouched
- All providers — untouched
- `AppBottomNav`, `MainScreen` — untouched
- `ApprovalTile` widget — no longer used in today screen (work screen still uses it)
