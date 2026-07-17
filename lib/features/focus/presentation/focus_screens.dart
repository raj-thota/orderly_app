import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/focus/data/focus_copy.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/focus/presentation/orbit.dart';

// ---------------------------------------------------------------------------
// Shared gradient decoration
// ---------------------------------------------------------------------------
const _kIndigoGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.62, 1.0],
    colors: [
      AppColors.briefGradientStart,
      AppColors.briefGradientEnd,
      Color(0xFF4A3EC0),
    ],
  ),
);

// ---------------------------------------------------------------------------
// 1. FocusEntryScreen
// ---------------------------------------------------------------------------

/// The invitation screen shown before a session begins.
///
/// When [resumeLeft] is non-null, renders the "Pick up where you left off?"
/// resume variant instead of the default entry copy.
class FocusEntryScreen extends StatelessWidget {
  const FocusEntryScreen({
    super.key,
    required this.firstName,
    required this.taskCount,
    required this.minutes,
    required this.onStart,
    required this.onDismiss,
    this.resumeLeft,
  });

  final String firstName;
  final int taskCount;
  final int minutes;
  final VoidCallback onStart;
  final VoidCallback onDismiss;

  /// When non-null, show the resume variant with this many tasks left.
  final int? resumeLeft;

  bool get _isResume => resumeLeft != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _kIndigoGradient,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    // Eyebrow label
                    Text(
                      _isResume ? 'WELCOME BACK' : 'FOCUS MODE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.16 * 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    // Orbit mascot
                    const Orbit(mood: OrbitMood.neutral, size: 120),
                    const SizedBox(height: AppSpacing.xl),
                    // Headline
                    Text(
                      _isResume
                          ? 'Pick up where\nyou left off?'
                          : 'Ready when you are,\n$firstName',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.02 * 27,
                        height: 1.14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Body copy
                    Text(
                      _isResume
                          ? "You finished ${taskCount - resumeLeft!} of $taskCount this morning. Just $resumeLeft left — about $minutes minutes."
                          : "I've lined up your $taskCount most important tasks for today. Let's clear them together.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Scope pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        _isResume
                            ? '⚡ ${resumeLeft!} tasks left · about $minutes min'
                            : '⚡ $taskCount tasks · about $minutes min',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.04 * 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Primary CTA
                    _WhiteButton(
                      buttonKey: const Key('focus_start'),
                      label: _isResume
                          ? 'Resume · ${resumeLeft!} left →'
                          : 'Start my work →',
                      onTap: onStart,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Subtle dismiss
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          _isResume ? 'Review all tasks' : 'Not now',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. FocusEmptyScreen
// ---------------------------------------------------------------------------

/// Shown when there are no tasks to work on — reassuring, never a dead end.
class FocusEmptyScreen extends StatelessWidget {
  const FocusEmptyScreen({super.key, required this.onBackHome});

  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _kIndigoGradient,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    const Spacer(),
                    const Orbit(mood: OrbitMood.happy, size: 118),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      "You're all caught up",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.02 * 27,
                        height: 1.14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      "Nothing needs you right now. I'll line up new work as it comes in and ping you.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Calm pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Text(
                        '🌤️ Enjoy the calm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.04 * 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _WhiteButton(label: 'Back to Home', onTap: onBackHome),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. FocusSuccessOverlay
// ---------------------------------------------------------------------------

/// Transient success moment shown after each task completion.
///
/// Animates a green checkmark stroke (~0.7 s), plus a pulse ring.
/// Calls [onDone] once the checkmark finishes (or immediately when
/// `MediaQuery.disableAnimations` is true).
class FocusSuccessOverlay extends StatefulWidget {
  const FocusSuccessOverlay({
    super.key,
    required this.progress,
    required this.line,
    required this.onDone,
  });

  /// Session progress 0..1, shown as a thin bar.
  final double progress;

  /// One-liner copy e.g. "Nice work! Just 2 more to go."
  final String line;

  /// Called once the checkmark animation completes.
  final VoidCallback onDone;

  @override
  State<FocusSuccessOverlay> createState() => _FocusSuccessOverlayState();
}

class _FocusSuccessOverlayState extends State<FocusSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _checkAnim;
  late final Animation<double> _pulseAnim;
  bool _doneFired = false;

  // Total: circle draws 0–0.6, checkmark draws 0.55–1.0, done fired at 1.0
  static const Duration _totalDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _totalDuration);

    _checkAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _pulseAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_doneFired) {
        _doneFired = true;
        widget.onDone();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      if (!_doneFired) {
        _doneFired = true;
        // Fire after the frame so the widget tree is settled.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onDone();
        });
      }
    } else {
      if (_ctrl.status == AnimationStatus.dismissed) _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1EFFE), // lilac wash
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Checkmark ring with animated check
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulse ring
                        CustomPaint(
                          size: const Size(120, 120),
                          painter: _PulseRingPainter(
                            progress: _pulseAnim.value,
                          ),
                        ),
                        // White ring background
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x1A111827),
                                blurRadius: 30,
                                offset: Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Color(0x0D111827),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        // Animated checkmark
                        CustomPaint(
                          size: const Size(66, 66),
                          painter: _CheckPainter(
                            progress: _checkAnim.value,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              // Main line
              Text(
                widget.line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.02 * 24,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Progress bar
              SizedBox(
                width: 170,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: widget.progress.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE7E4F7),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${(widget.progress * 100).round()}% complete',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress});
  final double progress;

  // Circle draws 0..0.6, tick draws 0.6..1.0
  static const double _circleEnd = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) * 0.85; // ~34/40 of half-size

    final circlePaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Circle arc
    final circleProgress = math.min(progress / _circleEnd, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      2 * math.pi * circleProgress,
      false,
      circlePaint,
    );

    // Checkmark tick (only once circle is ≥60% done)
    if (progress > _circleEnd) {
      final tickProgress = (progress - _circleEnd) / (1.0 - _circleEnd);
      _drawTick(canvas, size, tickProgress);
    }
  }

  void _drawTick(Canvas canvas, Size size, double t) {
    // Tick: M24 41 L36 53 L57 30 in a 80×80 viewBox; scale to size
    final scale = size.width / 80;
    final tickPaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * (size.width / 66)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Segment 1: (24,41) → (36,53)  length ~17
    // Segment 2: (36,53) → (57,30)  length ~31
    // Total ~48; ratio ≈ 17/48 ≈ 0.35
    const s1Ratio = 0.35;

    final p0 = Offset(24 * scale, 41 * scale);
    final p1 = Offset(36 * scale, 53 * scale);
    final p2 = Offset(57 * scale, 30 * scale);

    final path = Path();
    if (t <= s1Ratio) {
      final tt = t / s1Ratio;
      path.moveTo(p0.dx, p0.dy);
      path.lineTo(
        p0.dx + (p1.dx - p0.dx) * tt,
        p0.dy + (p1.dy - p0.dy) * tt,
      );
    } else {
      final tt = (t - s1Ratio) / (1.0 - s1Ratio);
      path.moveTo(p0.dx, p0.dy);
      path.lineTo(p1.dx, p1.dy);
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * tt,
        p1.dy + (p2.dy - p1.dy) * tt,
      );
    }
    canvas.drawPath(path, tickPaint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Ring expands from r=48 to r=60 and fades out
    final radius = 48 + 12 * progress;
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.25;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.success.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// 4. FocusFinishScreen
// ---------------------------------------------------------------------------

/// The dopamine moment — all tasks done, session summary, back to home.
class FocusFinishScreen extends StatelessWidget {
  const FocusFinishScreen({
    super.key,
    required this.firstName,
    required this.summary,
    required this.onDone,
  });

  final String firstName;
  final FocusSummary summary;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _kIndigoGradient,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'ALL DONE 🎉',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.16 * 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Orbit(mood: OrbitMood.celebrating, size: 104),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      "Everything's complete",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.02 * 27,
                        height: 1.14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    Text(
                      focusFinishLine(firstName),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Summary card
                    _SummaryCard(summary: summary),
                    const Spacer(),
                    const SizedBox(height: AppSpacing.xl),
                    _WhiteButton(
                      buttonKey: const Key('focus_done'),
                      label: 'Back to Home',
                      onTap: onDone,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final FocusSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: '✅',
            label: 'Tasks completed',
            value: '${summary.tasksCompleted}',
          ),
          _SummaryRow(
            icon: '💰',
            label: 'Payments followed up',
            value: Money.inr(summary.amountFollowedUp),
          ),
          _SummaryRow(
            icon: '💬',
            label: 'Customers replied to',
            value: '${summary.repliesSent}',
          ),
          _SummaryRow(
            icon: '📦',
            label: 'Orders confirmed',
            value: '${summary.offersSent}',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg - 1,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
      ),
      child: Row(
        children: [
          // Icon chip
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm - 2),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared white button
// ---------------------------------------------------------------------------

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({
    // key intentionally NOT forwarded to super — callers pass it via Key()
    // on the ElevatedButton only so tests see exactly one widget per key.
    Key? buttonKey,
    required this.label,
    required this.onTap,
  }) : _buttonKey = buttonKey;

  final Key? _buttonKey;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        key: _buttonKey,
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
