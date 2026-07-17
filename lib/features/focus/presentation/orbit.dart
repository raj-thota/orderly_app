import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Design tokens (Orbit-specific, derived from the approved expression set)
// ---------------------------------------------------------------------------
const Color _kMint = Color(0xFF66E0C8);
const Color _kVisor = Color(0xFF241F45);
const Color _kBlush = Color(0xFFFFB9D2);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// The four moods that drive Orbit's facial expression.
enum OrbitMood { neutral, thinking, happy, celebrating }

/// Orbit — the AI mascot for Focus Mode.
///
/// Renders at any [size] in any of the four [OrbitMood]s.
/// Plays a gentle bob + periodic blink when animations are enabled.
/// Respects `MediaQuery.disableAnimations` for reduced-motion users.
class Orbit extends StatefulWidget {
  const Orbit({
    super.key,
    required this.mood,
    this.size = 120,
  });

  final OrbitMood mood;
  final double size;

  @override
  State<Orbit> createState() => _OrbitState();
}

class _OrbitState extends State<Orbit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Bob: 0→1→0 over full period
  late final Animation<double> _bob;
  // Blink: drives eye scale-Y
  late final Animation<double> _blink;
  // Thinking dot pulse (offset into controller's cycle)
  late final Animation<double> _thinkPulse;
  // Celebrating sparkle twinkle
  late final Animation<double> _twinkle;
  // Tilt for thinking mood
  late final Animation<double> _tilt;

  static const Duration _period = Duration(milliseconds: 3400);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period)
      ..repeat();

    // Smooth bob: top at 0.5 of the period
    _bob = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Blink: most of the time scaleY=1, dips at 96% of cycle
    _blink = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 92),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.08)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 4),
      TweenSequenceItem(
          tween: Tween(begin: 0.08, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 4),
    ]).animate(_controller);

    // Thinking dots: oscillate opacity independently
    _thinkPulse = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.3, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.3)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
    ]).animate(_controller);

    // Celebrating twinkle: scale 0.8→1.15
    _twinkle = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.8, end: 1.15)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.15, end: 0.8)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
    ]).animate(_controller);

    // Tilt: -4° → +4° over period
    _tilt = Tween<double>(begin: -4 * math.pi / 180, end: 4 * math.pi / 180)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _animationsDisabled(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true;
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _animationsDisabled(context);
    if (disabled) {
      // Static frame — stop the controller if it's running
      if (_controller.isAnimating) _controller.stop();
      return _buildPainter(bobOffset: 0, blinkScale: 1, extra: 1, tilt: 0);
    } else {
      if (!_controller.isAnimating) _controller.repeat();
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Bob: translateY 0 → -7px → 0
          final bobOffset = math.sin(_bob.value * math.pi) * -7.0;
          return _buildPainter(
            bobOffset: bobOffset,
            blinkScale: _blink.value,
            extra: _thinkPulse.value,
            twinkle: _twinkle.value,
            tilt: widget.mood == OrbitMood.thinking ? _tilt.value : 0,
          );
        },
      );
    }
  }

  Widget _buildPainter({
    required double bobOffset,
    required double blinkScale,
    required double extra,
    double twinkle = 1.0,
    double tilt = 0,
  }) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.translate(
        offset: Offset(0, bobOffset),
        child: Transform.rotate(
          angle: tilt,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _OrbitPainter(
              mood: widget.mood,
              blinkScale: blinkScale,
              thinkPulse: extra,
              twinkle: twinkle,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.mood,
    required this.blinkScale,
    required this.thinkPulse,
    required this.twinkle,
  });

  final OrbitMood mood;
  final double blinkScale;   // 0..1 eye scale-Y for blink
  final double thinkPulse;   // 0.3..1 opacity for thinking dots
  final double twinkle;      // 0.8..1.15 scale for sparkles

  @override
  void paint(Canvas canvas, Size size) {
    // All SVG coordinates are in a 150×150 viewBox; scale to actual size.
    final scale = size.width / 150;
    canvas.scale(scale, scale);

    _drawCelebrationArms(canvas);    // behind body for celebrating
    _drawBody(canvas);
    _drawAntenna(canvas);
    _drawVisor(canvas);
    _drawFace(canvas);
    _drawBlush(canvas);
    if (mood == OrbitMood.thinking) _drawThinkingDots(canvas);
    if (mood == OrbitMood.celebrating) _drawSparkles(canvas);
  }

  // --- Body & shadow ---

  void _drawBody(Canvas canvas) {
    // Shadow ellipse
    final shadowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(const Rect.fromLTWH(35, 108, 80, 24), shadowPaint);

    // Body: white rounded rect (33,40 → 84×82 → rx 41)
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(33, 40, 84, 82),
      const Radius.circular(41),
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFEEF0FF)],
      ).createShader(const Rect.fromLTWH(33, 40, 84, 82));
    canvas.drawRRect(bodyRect, bodyPaint);

    final bodyStroke = Paint()
      ..color = const Color(0xFFE3E1F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(bodyRect, bodyStroke);
  }

  // --- Antenna ---

  void _drawAntenna(Canvas canvas) {
    final stemPaint = Paint()
      ..color = const Color(0xFF8B7FF5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(75, 40), const Offset(75, 27), stemPaint);
    canvas.drawCircle(
      const Offset(75, 23),
      5,
      Paint()..color = AppColors.accent,
    );
  }

  // --- Visor ---

  void _drawVisor(Canvas canvas) {
    final visorRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(47, 60, 56, 36),
      const Radius.circular(18),
    );
    canvas.drawRRect(visorRect, Paint()..color = _kVisor);

    // Visor glare (ellipse at top-left)
    canvas.drawOval(
      const Rect.fromLTWH(47, 60, 24, 12),
      Paint()..color = const Color(0xFF3A3168).withValues(alpha: 0.6),
    );
  }

  // --- Face (eyes/mouth depending on mood) ---

  void _drawFace(Canvas canvas) {
    switch (mood) {
      case OrbitMood.neutral:
        _drawNeutralEyes(canvas);
      case OrbitMood.thinking:
        _drawThinkingEyes(canvas);
      case OrbitMood.happy:
        _drawHappyEyes(canvas);
      case OrbitMood.celebrating:
        _drawCelebratingFace(canvas);
    }
  }

  void _drawNeutralEyes(Canvas canvas) {
    final eyePaint = Paint()..color = const Color(0xFF9D8BFF);
    // Save/restore for blink scale-Y on each eye
    for (final cx in [64.0, 86.0]) {
      canvas.save();
      canvas.translate(cx, 78);
      canvas.scale(1.0, blinkScale);
      canvas.drawCircle(Offset.zero, 7, eyePaint);
      canvas.restore();
      // White catchlight — stays full size
      canvas.drawCircle(
        Offset(cx + 2, 76),
        2.2,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawThinkingEyes(Canvas canvas) {
    // Eyes look up: centers at (63,74) and (85,74) instead of (64,78)/(86,78)
    final eyePaint = Paint()..color = const Color(0xFF9D8BFF);
    for (final cx in [63.0, 85.0]) {
      canvas.save();
      canvas.translate(cx, 74);
      canvas.scale(1.0, blinkScale);
      canvas.drawCircle(Offset.zero, 6.5, eyePaint);
      canvas.restore();
      canvas.drawCircle(
        Offset(cx + 2, 72),
        2,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawHappyEyes(Canvas canvas) {
    // ^ ^ arc eyes — mint upward curves
    final arcPaint = Paint()
      ..color = _kMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // Left eye: M56 82 Q64 72 72 82
    final leftPath = Path()
      ..moveTo(56, 82)
      ..quadraticBezierTo(64, 72, 72, 82);
    canvas.drawPath(leftPath, arcPaint);
    // Right eye: M78 82 Q86 72 94 82
    final rightPath = Path()
      ..moveTo(78, 82)
      ..quadraticBezierTo(86, 72, 94, 82);
    canvas.drawPath(rightPath, arcPaint);
  }

  void _drawCelebratingFace(Canvas canvas) {
    // Same ^ ^ eyes as happy
    final arcPaint = Paint()
      ..color = _kMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final leftEye = Path()
      ..moveTo(56, 78)
      ..quadraticBezierTo(64, 68, 72, 78);
    final rightEye = Path()
      ..moveTo(78, 78)
      ..quadraticBezierTo(86, 68, 94, 78);
    canvas.drawPath(leftEye, arcPaint);
    canvas.drawPath(rightEye, arcPaint);

    // Open smile: ellipse at (75,90) rx7 ry5
    canvas.drawOval(
      const Rect.fromLTWH(68, 85, 14, 10),
      Paint()..color = _kMint,
    );
  }

  // --- Blush cheeks ---

  void _drawBlush(Canvas canvas) {
    final blushPaint = Paint()
      ..color = _kBlush.withValues(alpha: mood == OrbitMood.happy ? 1.0 : 0.75);
    final cy = mood == OrbitMood.celebrating ? 90.0 : 88.0;
    final r = (mood == OrbitMood.happy || mood == OrbitMood.celebrating)
        ? 5.5
        : 4.5;
    canvas.drawCircle(Offset(42, cy), r, blushPaint);
    canvas.drawCircle(Offset(108, cy), r, blushPaint);
  }

  // --- Thinking dots (upper-right orbiting) ---

  void _drawThinkingDots(Canvas canvas) {
    // Three dots rising to upper-right with staggered pulse
    final dotPaint = Paint()..color = const Color(0xFF8B7FF5);
    final opacities = [
      thinkPulse.clamp(0.3, 1.0),
      (thinkPulse * 0.8 + 0.2).clamp(0.3, 1.0),
      (thinkPulse * 0.6 + 0.4).clamp(0.3, 1.0),
    ];
    final positions = [
      const Offset(98, 46),
      const Offset(107, 40),
      const Offset(117, 35),
    ];
    final radii = [3.0, 3.5, 4.0];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        positions[i],
        radii[i],
        dotPaint..color = const Color(0xFF8B7FF5).withValues(alpha: opacities[i]),
      );
    }
  }

  // --- Celebration arms (raised arms, drawn behind body) ---

  void _drawCelebrationArms(Canvas canvas) {
    if (mood != OrbitMood.celebrating) return;
    final armPaint = Paint()
      ..color = const Color(0xFFEEF0FF)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    // Left arm: M40 70 L26 58
    canvas.drawLine(const Offset(40, 70), const Offset(26, 58), armPaint);
    // Right arm: M110 70 L124 58
    canvas.drawLine(const Offset(110, 70), const Offset(124, 58), armPaint);
  }

  // --- Sparkles for celebrating ---

  void _drawSparkles(Canvas canvas) {
    // Gold sparkle at (28,40), lilac at (120,46)
    _drawSparkle(
        canvas, const Offset(28, 40), AppColors.accent, twinkle);
    _drawSparkle(
        canvas, const Offset(120, 46), const Color(0xFF7C6BF7), twinkle);
  }

  void _drawSparkle(Canvas canvas, Offset center, Color color, double scale) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    final paint = Paint()..color = color;
    // 4-point star path: l2 5 5 2 -5 2 -2 5 -2 -5 -5 -2 5 -2
    final path = Path()
      ..moveTo(0, 0)
      ..relativeLineTo(2, 5)
      ..relativeLineTo(5, 2)
      ..relativeLineTo(-5, 2)
      ..relativeLineTo(-2, 5)
      ..relativeLineTo(-2, -5)
      ..relativeLineTo(-5, -2)
      ..relativeLineTo(5, -2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.mood != mood ||
      old.blinkScale != blinkScale ||
      old.thinkPulse != thinkPulse ||
      old.twinkle != twinkle;
}
