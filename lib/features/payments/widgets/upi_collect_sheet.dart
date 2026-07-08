import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Bottom sheet showing a scannable UPI QR plus a WhatsApp share action.
/// Presentation only: [onShareWhatsApp] performs the launch.
class UpiCollectSheet extends StatelessWidget {
  const UpiCollectSheet({
    super.key,
    required this.amount,
    required this.upiUri,
    required this.vpa,
    this.vpaName,
    required this.onShareWhatsApp,
  });

  final double amount;
  final String upiUri;
  final String vpa;
  final String? vpaName;
  final VoidCallback onShareWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Collect ${Money.inr(amount)} via UPI',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: QrImageView(
              data: upiUri,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(vpaName == null || vpaName!.isEmpty ? vpa : '$vpa ($vpaName)',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onShareWhatsApp,
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Send payment link on WhatsApp'),
            ),
          ),
        ],
      ),
    );
  }
}
