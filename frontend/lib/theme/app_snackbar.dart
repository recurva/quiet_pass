import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'dimens.dart';
import 'theme_x.dart';

/// A themed replacement for the default (unstyled, always-white) Material
/// SnackBar. Every call site that needs to surface a backend error uses
/// this instead of `ScaffoldMessenger...SnackBar(...)` directly, so error
/// messages never break the dark/light theme.
void showAppSnackBar(BuildContext context, String message) {
  final c = context.colors;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md.r),
        side: BorderSide(color: c.line2),
      ),
      margin: EdgeInsets.all(Space.base.w),
      content: Text(
        message,
        style: context.text.bodyMedium?.copyWith(color: c.ink),
      ),
    ),
  );
}
