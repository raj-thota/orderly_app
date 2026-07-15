import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({super.key, required this.confidence});

  final double confidence;

  Color get _color {
    if (confidence >= 0.8) return AppColors.success;
    if (confidence >= 0.5) return AppColors.info;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              backgroundColor: AppColors.border,
              color: _color,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _color,
          ),
        ),
      ],
    );
  }
}
