import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';

import 'review_confirm_screen.dart';

class ExtractionProgressScreen extends ConsumerStatefulWidget {
  const ExtractionProgressScreen({super.key});

  @override
  ConsumerState<ExtractionProgressScreen> createState() =>
      _ExtractionProgressScreenState();
}

class _ExtractionProgressScreenState
    extends ConsumerState<ExtractionProgressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Advance immediately if AI is already done (e.g. manual entry).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(captureControllerProvider);
      if (!state.aiRefining) _goToReview();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _goToReview() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ReviewConfirmScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(captureControllerProvider, (prev, next) {
      if (prev?.aiRefining == true && !next.aiRefining) _goToReview();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary
                          .withAlpha(((_pulse.value * 0.3 + 0.1) * 255).round()),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.primary, size: 40),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Closr AI is reading…',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Extracting customer, products and intent',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _StepRow(label: 'Reading chat', done: true),
                const SizedBox(height: AppSpacing.sm),
                const _StepRow(label: 'Identifying customer', done: true),
                const SizedBox(height: AppSpacing.sm),
                const _StepRow(label: 'Understanding intent', loading: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, this.done = false, this.loading = false});
  final String label;
  final bool done;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 18)
        else if (loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          )
        else
          const Icon(Icons.circle_outlined,
              color: AppColors.border, size: 18),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              fontSize: 14,
              color: done || loading
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            )),
      ],
    );
  }
}
