# Home Screen Redesign — AI Copilot Brief

**Date:** 2026-07-15
**Branch:** mvp_release
**Scope:** `lib/features/today/` + tests

---

## Why a redesign

The previous Today tab read like a dashboard: the hero was a 4-row metric card,
insights lived in an auto-rotating 4-second carousel (only one visible at a
time), and the same 3 AI work items rendered twice ("Needs your attention" list
+ "AI suggested actions" cards). No recent activity, no quick actions.

Closr's promise is an AI copilot that tells the owner what to do next. The
Home screen should speak first and show numbers second.

## Principles

1. **Assistant speaks first, evidence follows.** The hero is a narrative brief
   built from live data, not a stat grid.
2. **One item, one row, one action.** Work queue tiles carry their direct CTA
   (call / WhatsApp / workspace); no duplicate card rail.
3. **Insights are advice, not metric echoes.** Each card has a title and a
   "why it matters" line, stacked statically — no timers hiding content.
4. **Analytics support decisions.** Metrics demoted to a compact 2×2 snapshot
   grid mid-page.

## Section order (top → bottom = attention priority)

1. **Greeting** — date eyebrow (`TUESDAY, 15 JULY`) + `Good morning, {name} 👋`.
2. **AI brief (hero)** — gradient card:
   - Eyebrow `YOUR MORNING/AFTERNOON/EVENING BRIEF` + sparkle.
   - Narrative paragraph from `buildBriefNarrative(brief, items, now)`:
     counts pending work, sums collectable ₹, counts waiting replies and
     win-back offers; evening variant celebrates revenue; all-clear variant
     suggests what to do with free time. Small robo mascot (64px) beside text.
   - Session meta line: `5 tasks · about 10 min` (from `estimatedMinutes`),
     so the CTA reads as starting a bounded work session.
   - CTA `Start My Work →` → My Work tab.
3. **Today's work** — compact checklist card, top 4 `AiWorkItem`s. Row =
   priority dot + task sentence (`focusLabel`: "Collect ₹8,597 from Aman") +
   per-task minutes + chevron. Tap → customer workspace. Footer:
   `Estimated completion · about N min`. Bridges the brief and insights.
4. **AI insights** — action-first cards from
   `buildHomeInsights(brief, now: now)`: verb title
   ("Collect outstanding payments"), evidence line
   ("₹42,092 is pending across 7 orders." / "Meera has been waiting 8 hours."),
   CTA ("Send reminders →"). Lilac `aiSurface` cards, hidden when empty.
5. **Business snapshot** — 2×2 grid: Orders today, Revenue today, Outstanding,
   Follow-ups due. Keys `snap_*` for tests.
6. **Recent activity** — `buildRecentActivity(orders)`: event headline
   ("Payment received") + `name · time` subtitle + money right-aligned
   (payments green `+₹`), newest first, max 5, tap → `OrderDetailScreen`.
   Hidden when empty.
7. **Quick actions** — New sale (`CaptureSheet`), Payments (Orders tab),
   Catalog, Invoices — ordered by expected frequency.

## Visual system

White cards use one soft shadow token (`_cardShadow`, black 5% / blur 14 /
y-offset 4) instead of hairline borders; dividers remain hairlines inside
list cards. Section gap `AppSpacing.xl`.

## Data layer (pure, unit-tested)

| File | Exports |
|---|---|
| `data/brief_narrative.dart` | `BriefDaypart`, `briefDaypart`, `BriefNarrative`, `buildBriefNarrative`, `focusLabel`, `estimatedMinutesFor`, `estimatedMinutes` |
| `data/home_insight.dart` | `HomeInsightKind`, `HomeInsight` (title/evidence/cta), `buildHomeInsights` |
| `data/recent_activity.dart` | `ActivityKind`, `ActivityEntry`, `buildRecentActivity` |

`TodayBrief` gained `outstandingCount`, `dueName`, `dueSince` so insights can
say who is waiting and across how many orders. Providers, nav shell unchanged;
`ai_card_action.dart` now used only by the work screen.

## Removed

- Auto-rotating nudge carousel (+ its `Timer`).
- `_AiActionCard` horizontal rail and heavy `_WorkQueueTile` (both replaced by
  the compact checklist; per-item direct actions live in the workspace).
- `_StatRow` metric rows and the "First up" chip inside the hero (the
  checklist directly below the hero is the priority pointer — same fact never
  stated twice).

## Test coverage

- `brief_narrative_test.dart` — dayparts, grammar, evening wrap, focus labels.
- `home_insight_test.dart` — derivation order, plurals, target tabs.
- `recent_activity_test.dart` — flattening, sorting, limit, skips.
- `today_screen_test.dart` — rewritten for new sections; keeps avatar,
  badge, workspace-push, and event-tracking coverage.
