import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/utils/money.dart';

/// Renders a money value with INR formatting. Green for positive, red for dues.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.colorBySign = false,
  });

  final num value;
  final TextStyle? style;
  final bool colorBySign;

  @override
  Widget build(BuildContext context) {
    final base = style ??
        const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary);
    final color = colorBySign
        ? (value < 0 ? AppColors.dues : AppColors.money)
        : base.color;
    return Text(Money.inr(value), style: base.copyWith(color: color));
  }
}
