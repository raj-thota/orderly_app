import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/focus_session_provider.dart';
import '../data/focus_copy.dart';
import '../data/focus_session_store.dart';
import '../data/focus_snapshot.dart';
import '../../work/controller/work_items_provider.dart';
import 'focus_overlays.dart';
import 'focus_screens.dart';
import 'focus_task_card.dart';
import 'orbit.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Pushes FocusModeView as a full-screen dialog.
class FocusMode {
  static Future<void> start(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const FocusModeView(),
        ),
      );
}

// ---------------------------------------------------------------------------
// Pre-session local state
// ---------------------------------------------------------------------------

/// Phase before the user taps Start; determined by prefs + work items.
enum _PrePhase { loading, entry, resume, empty }

// ---------------------------------------------------------------------------
// FocusModeView
// ---------------------------------------------------------------------------

class FocusModeView extends ConsumerStatefulWidget {
  const FocusModeView({super.key});

  @override
  ConsumerState<FocusModeView> createState() => _FocusModeViewState();
}

class _FocusModeViewState extends ConsumerState<FocusModeView> {
  _PrePhase _prePhase = _PrePhase.loading;
  int _resumeLeft = 0;

  late FocusSessionStore _store;

  // First name, sourced from Supabase auth metadata.
  // Falls back to 'there' — never blocks the flow.
  String _firstName = 'there';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // ── Name ────────────────────────────────────────────────────────────────
    _firstName = _resolveFirstName();

    // ── Work items ──────────────────────────────────────────────────────────
    if (ref.read(workItemsProvider).items.isEmpty) {
      await ref.read(workItemsProvider.notifier).load();
    }
    final items = ref.read(workItemsProvider).items;

    // ── SharedPreferences + snapshot ────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    _store = FocusSessionStore(prefs);
    final snapshot = await _store.read();

    // ── Decide phase ────────────────────────────────────────────────────────
    if (!mounted) return;
    if (items.isEmpty) {
      setState(() => _prePhase = _PrePhase.empty);
      return;
    }
    final now = DateTime.now();
    if (snapshot != null &&
        snapshot.isResumable(
            currentBatchId: items.first.batchId, now: now)) {
      setState(() {
        _resumeLeft = snapshot.remaining;
        _prePhase = _PrePhase.resume;
      });
    } else {
      setState(() => _prePhase = _PrePhase.entry);
    }
  }

  /// Extracts the first token of the user's display name from Supabase auth
  /// metadata. Falls back to 'there'. Guarded — never throws in test contexts
  /// where Supabase is not initialised.
  String _resolveFirstName() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final meta = user?.userMetadata ?? {};
      final fullName = (meta['full_name'] ?? meta['name'] ?? '') as String;
      final trimmed = fullName.trim();
      if (trimmed.isEmpty) return 'there';
      return trimmed.split(RegExp(r'\s+')).first;
    } catch (_) {
      return 'there';
    }
  }

  // ── Session start ──────────────────────────────────────────────────────────

  Future<void> _startSession() async {
    await ref
        .read(focusSessionProvider.notifier)
        .start(now: DateTime.now());
  }

  // ── Primary action (WhatsApp / workspace) ──────────────────────────────────

  Future<void> _runPrimary() async {
    final state = ref.read(focusSessionProvider);
    final item = state.session?.current;
    if (item == null) return;

    // Clear any prior error so UI doesn't show stale toast.
    ref.read(focusSessionProvider.notifier).clearError();

    // Build WhatsApp URL.
    final phone = item.phone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
    final base = 'https://wa.me/91$phone';
    final draft = item.draftMessage;
    final url = (draft != null && draft.isNotEmpty)
        ? '$base?text=${Uri.encodeComponent(draft)}'
        : base;

    // Attempt launch then mark complete on the server.
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      await ref.read(focusSessionProvider.notifier).completeCurrent();
      await _persist();
      HapticFeedback.mediumImpact();
    } catch (_) {
      // completeCurrent not called → provider error stays null.
      // Force an error so the toast shows via a fire-and-catch on complete.
      // Simplest approach: call completeCurrent anyway so its catch sets
      // actionError — but that would mark the item done. Instead we set
      // a deliberate error by invoking completeCurrent on a guard that
      // throws: we use the notifier's own completeCurrent which wraps in
      // try/catch and sets actionError if approve throws.
      // For launch failure we simply show a local error via the provider by
      // surfacing it through a synthetic error string on the provider.
      // Cleanest: call completeCurrent with a wrapped service that has already
      // thrown — instead, just call the public clearError/set path if we had
      // it. We don't have a setError method, so use a minimal workaround:
      // call completeCurrent — if it succeeds it advances, if it throws it
      // sets actionError. But launch failure (not approve failure) means the
      // service call never ran. For V1, treat a launch failure as a
      // non-critical no-op and rely on the error UI only when approve fails.
      // No additional state needed: the toast is driven by actionError which
      // is only set by completeCurrent's catch. We do nothing here so the
      // user can retry by tapping the primary button again.
      //
      // This is the cleanest correct behaviour: url_launcher failure on most
      // devices means WhatsApp isn't installed; showing the task again lets
      // the user tap Mark done manually.
    }
  }

  // ── Skip ───────────────────────────────────────────────────────────────────

  Future<void> _skip() async {
    final state = ref.read(focusSessionProvider);
    final item = state.session?.current;
    if (item == null) return;

    final confirmed = await showFocusSkipSheet(
      context,
      customerName: item.customerName ?? 'customer',
    );
    if (!confirmed) return;

    ref.read(focusSessionProvider.notifier).skipCurrent();
    await _persist();
    HapticFeedback.selectionClick();
  }

  // ── Mark done ──────────────────────────────────────────────────────────────

  Future<void> _markDone() async {
    await ref
        .read(focusSessionProvider.notifier)
        .completeCurrent(markDone: true);
    await _persist();
    HapticFeedback.mediumImpact();
  }

  // ── Confirm exit ───────────────────────────────────────────────────────────

  Future<void> _confirmExit() async {
    final state = ref.read(focusSessionProvider);
    final s = state.session;
    final leave = await showFocusExitDialog(
      context,
      done: s?.completedCount ?? 0,
      total: s?.sessionTotal ?? 0,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  // ── Finish ─────────────────────────────────────────────────────────────────

  Future<void> _finishAndClose() async {
    await _store.clear();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Persist snapshot ────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final s = ref.read(focusSessionProvider).session;
    if (s == null) return;
    await _store.save(FocusSnapshot(
      batchId: s.batchId,
      orderedIds: s.queue.map((i) => i.id).toList(),
      completedIds: s.completed.map((i) => i.id).toList(),
      skippedIds: s.skippedIds.toList(),
      sessionTotal: s.sessionTotal,
      startedAt: s.startedAt,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(focusSessionProvider);
    final status = state.status;
    final s = state.session;

    // Before the session is started, use local _prePhase.
    final bool sessionStarted = status != FocusStatus.entry;

    return PopScope(
      // Allow normal pop only in pre-start phases (entry/resume/empty/loading)
      // or after the session is finished. During active flow, intercept and
      // show exit confirmation.
      canPop: !sessionStarted ||
          status == FocusStatus.finished ||
          status == FocusStatus.empty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && sessionStarted && status == FocusStatus.active) {
          _confirmExit();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildForState(state, status, s, sessionStarted),
      ),
    );
  }

  Widget _buildForState(
    FocusModeState state,
    FocusStatus status,
    dynamic s, // FocusSession?
    bool sessionStarted,
  ) {
    // Pre-start phases.
    if (!sessionStarted || status == FocusStatus.entry) {
      switch (_prePhase) {
        case _PrePhase.loading:
          return const Scaffold(
            key: ValueKey('loading'),
            body: Center(child: CircularProgressIndicator()),
          );
        case _PrePhase.empty:
          return FocusEmptyScreen(
            key: const ValueKey('empty'),
            onBackHome: () => Navigator.of(context).pop(),
          );
        case _PrePhase.entry:
          return _entryScreen(key: const ValueKey('entry'));
        case _PrePhase.resume:
          return _entryScreen(
            key: const ValueKey('resume'),
            resumeLeft: _resumeLeft,
          );
      }
    }

    // Session phases.
    switch (status) {
      case FocusStatus.entry:
        // Shouldn't reach here after session is started, but guard.
        return _entryScreen(key: const ValueKey('entry'));
      case FocusStatus.empty:
        return FocusEmptyScreen(
          key: const ValueKey('empty'),
          onBackHome: () => Navigator.of(context).pop(),
        );
      case FocusStatus.active:
        return _buildActiveScreen(state, s);
      case FocusStatus.celebrating:
        return FocusSuccessOverlay(
          key: const ValueKey('celebrating'),
          progress: s?.progress ?? 0,
          line: focusSuccessLine(s?.queue.length ?? 0),
          onDone: () {
            ref.read(focusSessionProvider.notifier).advance();
            // After advance, if the session is finished, clear the store.
            final newStatus = ref.read(focusSessionProvider).status;
            if (newStatus == FocusStatus.finished) {
              _store.clear();
            }
          },
        );
      case FocusStatus.finished:
        return FocusFinishScreen(
          key: const ValueKey('finished'),
          firstName: _firstName,
          summary: s!.summary(),
          onDone: _finishAndClose,
        );
      case FocusStatus.resume:
        return _entryScreen(
          key: const ValueKey('resume'),
          resumeLeft: _resumeLeft,
        );
    }
  }

  Widget _entryScreen({Key? key, int? resumeLeft}) {
    final items = ref.read(workItemsProvider).items;
    final taskCount = items.length;
    final minutes = items.fold<int>(
      0,
      (sum, item) {
        // Rough estimate: 2 min per task; this mirrors FocusSession.remainingMinutes
        // but we don't have a session yet, so approximate here.
        return sum + 2;
      },
    );

    return FocusEntryScreen(
      key: key,
      firstName: _firstName,
      taskCount: resumeLeft ?? taskCount,
      minutes: minutes,
      resumeLeft: resumeLeft,
      onStart: _startSession,
      onDismiss: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildActiveScreen(FocusModeState state, dynamic s) {
    if (s == null || s.current == null) {
      return const Scaffold(
        key: ValueKey('active_empty'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final item = s.current!;

    return Scaffold(
      key: const ValueKey('active'),
      backgroundColor: const Color(0xFFF7F6FE),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _confirmExit,
                    child: const Icon(Icons.close_rounded, size: 24),
                  ),
                  const Expanded(
                    child: Text(
                      'FOCUS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                        color: Color(0xFF4B40C4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24), // balance the ✕
                ],
              ),
            ),
            // ── Progress header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Task ${s.position} of ${s.sessionTotal}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4B40C4),
                        ),
                      ),
                      Text(
                        '≈ ${s.remainingMinutes} min left',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: s.progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE7E4F7),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4B40C4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Task card (scrollable) ────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Orbit + lead line
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(disableAnimations: true),
                          child: const Orbit(mood: OrbitMood.neutral, size: 32),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            focusTaskLead(item.kind, item.customerName?.split(' ').first ?? _firstName),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4B40C4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Error toast (above card)
                    if (state.actionError != null) ...[
                      FocusErrorToast(
                        customerName: item.customerName ?? 'customer',
                        onRetry: _runPrimary,
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Task card
                    FocusTaskCard(
                      item: item,
                      canSkip: s.canSkip,
                      onPrimary: _runPrimary,
                      onSkip: _skip,
                      onMarkDone: _markDone,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
