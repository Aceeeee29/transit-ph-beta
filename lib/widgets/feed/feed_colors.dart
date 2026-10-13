import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Shared color tokens for the Community Feed UI.
class FeedColors {
  FeedColors._();

  static Color get bg => AppColors.bg;
  static Color get surface => AppColors.surface;
  static Color get surfaceAlt => AppColors.surfaceAlt;
  static const accent = Color(0xFF0B8FD6);
  static Color get accentSoft => AppColors.accentSoft;
  static Color get textPrimary => AppColors.textPrimary;
  static Color get textSecondary => AppColors.textSecondary;
  static Color get border => AppColors.border;
  static const danger = Color(0xFFE05C6A);
}
