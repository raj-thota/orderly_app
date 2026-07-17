# Start My Work — Focus Mode

**Date:** 2026-07-17
**Branch:** mvp_release
**Scope:** new `lib/features/focus/` + wire the two `Start My Work` entry points. No nav / IA changes.

---

## Why

Home now ends on a `Start My Work →` CTA that just jumps to the My Work tab — a
flat, filterable task list. That is a backlog, not guidance. Closr's promise is an
AI copilot that walks the owner through today's highest-priority work one task at a
time. Focus Mode is that walk: a calm, full-screen guided flow — Apple Setup /
Duolingo lesson / Linear Inbox — that reduces thinking, clicks and stress.

## Principles

1. **One task, one screen, one primary action.** Show only what the current task needs.
2. **Progress is always visible** and updates after every task.
3. **The AI (Orbit) is supportive, never chatty.** One short line per moment.
4. **Nothing is a dead end.** Skip, exit, error, empty all keep Orbit warm and offer a next step.
5. **Focus Mode is a lens, not a new source of truth.** It reads and mutates the same `ai_work_items` as My Work and Home, so completing a task syncs everywhere instantly.

## Scope

**In:** a full-screen guided flow over existing pending `AiWorkItem`s; entry, guided
task (template that flexes by kind), success micro-celebration, next-task transition,
skip, exit dialog, all-complete, empty, error, resume. Orbit mascot + expression set.
Local session persistence for resume.

**Out (explicit):** bottom nav, IndexedStack, the My Work list screen, Orders/Business/
Profile. New work-item *kinds* (e.g. confirm-order, book-shipment) — the template is
built to accept them, but V1 ships only the kinds that exist today. Server-side session
storage. New Supabase tables.

---

## Entry & route model

Focus Mode is a **pushed full-screen route**, not a tab — the nav shell in `main.dart`
is untouched.

- `TodayScreen` `Start My Work →` (`today_screen.dart:851`, currently `onNavigate(1)`)
  → `FocusMode.start(context)`.
- `MyWorkScreen` gains a primary `Start My Work` affordance that calls the same.
- `FocusMode.start` pushes `FocusModeRoute` (`fullscreenDialog: true`, custom
  fade-through transition). It owns its own `Navigator`-level scope and can be
  dismissed at any time back to whatever tab launched it.

If there are zero pending items at launch → the route opens directly on the **empty**
state (never a blank list). If a resumable session exists → opens on **resume**.

---

## Task model — one template, kind-driven body

Focus Mode reuses `AiWorkItem` and the category helpers already in
`today/data/brief_narrative.dart`. No model changes.

| Group | Existing kinds | Body block | Primary action | Verb |
|---|---|---|---|---|
| Collect | `payment_reminder`, `overdue_payment` | AI draft + pay link | launch WhatsApp w/ prefilled draft | **Send WhatsApp reminder** |
| Reply | `reply`, `follow_up`, `call` | incoming message + AI draft reply | launch WhatsApp w/ prefilled reply | **Send reply** |
| Offer | `share_catalog`, `offer` | offer summary | launch WhatsApp w/ catalog/offer | **Send offer** |

`focusPrimaryAction(item)` resolves `{label, icon, color, handler}` from kind, defaulting
to "Open in workspace" for any unknown kind so the flow never breaks. WhatsApp send reuses
the existing `launchUrl('https://wa.me/91${phone}')` + prefilled-message pattern from
`customer_workspace_screen.dart`. After a successful primary action the task is completed
via `workItemsProvider.approve(id)`; **Mark done** uses `markDone(id)`; **Skip** does *not*
call the provider — it requeues locally (see below).

The confirm-order / book-shipment templates shown in the mockups are future kinds; the
table above is the V1 set. Adding a kind = one row in `focusPrimaryAction` + one body
builder, no new screens.

---

## Screens (10 states)

Visuals approved in `.superpowers/brainstorm/…/focus-mode-full.html`. Design language =
current Closr: indigo gradient (`#7C6BF7→#5B4FE9`), lilac AI surfaces (`#F1EFFE`), white
soft-shadow cards, radius 20–24, large type. Mascot = **Orbit** (neutral / thinking /
happy / celebrating expression set).

1. **Entry** — indigo gradient. Orbit neutral (bob + blink). `Ready when you are, {name}`,
   scope pill `⚡ {n} tasks · about {m} min` (from `estimatedMinutes`). `Start my work →`
   (white) + `Not now`.
2. **Guided task** — white. Top: ✕ + `FOCUS` + progress row (`Task {i} of {n}`,
   breathing bar, `≈ {m} min left`). Orbit inline (32px) + one AI line. Task card:
   kind pill → big title (`focusLabel`) → why-line → customer chip → kind body → primary
   CTA → `Skip for now` / `Mark done ✓`.
3. **Success** — lilac wash. Checkmark draws + pulse ring + confetti. `Nice work! That's
   done.` + one-line context. Progress jumps. Auto-advances after ~1.4 s (haptic).
4. **Next-task transition** — fade-through into the next task card; AI line references the
   next customer. Same template, different kind body.
5. **Skip** — bottom sheet, Orbit thinking. `Skip this for now?` / "I'll bring it back at
   the end of your session." `Keep task` / `Skip →`. Requeues to end.
6. **Exit dialog** — centered modal on tap ✕. `Leave Focus Mode?` / "You've done {k} of
   {n} — I'll save your progress." `Leave` / `Keep going` (emphasised). Progress persisted.
7. **All complete** — indigo gradient, Orbit celebrating. `Everything's complete` + session
   summary (tasks done, payments followed up ₹, replies sent, orders confirmed) + `Back to
   Home`. Small dopamine moment.
8. **Empty** — gradient, Orbit happy. `You're all caught up` / "I'll line up new work and
   ping you." `Back to Home`. Reached when no pending items.
9. **Error** — inline toast (not a modal): `Couldn't send to {name}` / "your draft is
   safe." Orbit reassuring line. Card stays with `↻ Try again` / `Skip for now` / `Copy &
   send manually`. Draft preserved; flow continues.
10. **Resume** — gradient entry variant on relaunch. `Pick up where you left off?` / "{k}
    of {n} done — {m} min left." Progress dots. `Resume · {r} left →` / `Review all tasks`.

## Progress & AI copy

- Progress % = `completedThisSession / sessionTotal`. `sessionTotal` is frozen at session
  start so the denominator doesn't shift as items complete.
- Remaining minutes = sum of `estimatedMinutesFor(item)` over not-yet-done tasks (reuses
  existing per-kind heuristic).
- AI copy is deterministic from `{position, remaining, kind, daypart}` — no free-form
  generation. `focus_copy.dart` returns the entry line, per-task lead-in, success line,
  and finish line. Tone rules: ≤ ~8 words, encouraging, never more than one line.

## Session & resume persistence

- `FocusSessionStore` over `SharedPreferences` (no new table). Persists
  `{batchId, orderedIds, completedIds, skippedIds, startedAt, sessionTotal}`.
- On launch: if a stored session's `batchId` matches the current pending batch, `startedAt`
  is same-day, and remaining > 0 → **resume**; else start fresh and overwrite.
- Skip requeues an id to the tail of `orderedIds` (bounded: a task can be skipped at most
  once per session, then it's presented as the last item and must be actioned or exited).
- Server truth is unchanged: `approve`/`markDone`/`dismiss` still flip `ai_work_items.status`
  exactly as My Work does today.

## Sync back to the app

Focus Mode mutates through `workItemsProvider`, so its state and every screen watching it
(Home brief via `today_brief`, My Work list, in-app notifications) reflect completions with
no extra wiring. On dismiss of the route, the launching tab reloads as it already does on
`changeTab`.

## Motion, haptics, accessibility

- **Motion:** progress-bar tween on advance; checkmark stroke-draw; Orbit idle bob + blink,
  expression swap per state; confetti on success/finish; fade-through page transitions;
  button press-scale. Every animation maps to a state change — no idle decoration.
- **Haptics:** `HapticFeedback.mediumImpact()` on task complete, `lightImpact()` on advance
  and primary-button press, `selectionClick()` on skip.
- **Skeleton** shimmer for the task card during the initial item load.
- **A11y:** semantic labels per state; ≥ 44px tap targets; primary action pinned to the
  bottom third for one-handed reach; AA contrast; respects reduced-motion (swap animations
  for instant transitions).

---

## Architecture

New feature module `lib/features/focus/`, mirroring the existing feature layout
(`data/` pure + unit-tested, `controller/` Riverpod, `presentation/` widgets).

| File | Responsibility |
|---|---|
| `data/focus_session.dart` | Pure: build ordered queue from items, advance, skip-requeue, progress %, remaining minutes, session summary. No Flutter imports. |
| `data/focus_copy.dart` | Pure: deterministic AI copy per `{position, remaining, kind, daypart}`. |
| `data/focus_session_store.dart` | `SharedPreferences` persistence + resume-eligibility check. |
| `controller/focus_session_provider.dart` | `StateNotifier<FocusSessionState>` layered over `workItemsProvider`; owns queue/index/skip/status; calls `approve`/`markDone` for real mutations. |
| `presentation/focus_mode_route.dart` | Full-screen route + entry/resume/empty branching + fade-through between states. |
| `presentation/focus_task_card.dart` | Kind-driven task template + `focusPrimaryAction`. |
| `presentation/orbit.dart` | Orbit mascot widget with `OrbitMood { neutral, thinking, happy, celebrating }`. |
| `presentation/widgets/` | progress bar, success burst, skip sheet, exit dialog, error toast. |

**Isolation:** `data/` is pure Dart (fast unit tests, no I/O). The provider is the only
thing that touches `workItemsProvider`. Presentation reads the provider and renders a state
enum — each screen is a stateless function of `FocusSessionState`, independently testable.

## Testing (TDD)

- **Unit** — `focus_session_test.dart` (queue order by score, advance, skip requeues to
  tail + skip-once bound, frozen denominator, remaining minutes, summary tallies);
  `focus_copy_test.dart` (word-count bound, per-kind/position lines, daypart);
  `focus_session_store_test.dart` (persist/restore, same-day + batch-match resume rule).
- **Widget** — one test per state: entry scope pill, task card per kind group, success
  advance, exit-saves-progress, skip requeue, error keeps draft, empty, resume dots.
- **Regression** — completing in Focus Mode removes the item from `workItemsProvider`
  (asserts sync), and the launching tab reload path is unchanged.

## Future (not V1)

Confirm-order / book-shipment / win-back kinds; server-side session so resume crosses
devices; streak / weekly-momentum stats on the finish screen.
