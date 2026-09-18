import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Ergonomic access to the theme from any widget.
///
/// Instead of `Theme.of(context).extension<AppColors>()!` at every call site,
/// widgets use `context.colors.accent`, `context.text.titleLarge`, etc.
extension ThemeX on BuildContext {
  /// Semantic color tokens for the active mode.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  /// The Material text theme (Plus Jakarta Sans, configured in app_theme.dart).
  TextTheme get text => Theme.of(this).textTheme;

  /// True when the dark palette is active.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
