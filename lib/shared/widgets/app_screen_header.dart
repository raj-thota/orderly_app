import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

/// Consistent AppBar for the settings-family screens.
AppBar appScreenHeader(String title) => AppBar(
      title: Text(title),
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    );
