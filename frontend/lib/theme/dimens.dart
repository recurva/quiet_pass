import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Spacing and radius scale for QuietPass.
///
/// Every gap, padding, and corner in the app comes from here. Nothing sets a
/// raw pixel value inline. This is the layer that keeps layouts from breaking
/// across screen sizes: values scale through screenutil ([.w]/[.h]/[.r]) from
/// the 375x812 reference set in main.dart.
///
/// Use the `.w` extension for horizontal space, `.h` for vertical, and `.r`
/// for radii and square sizes, e.g. `SizedBox(height: Space.base.h)`.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Convenience getters so call sites read cleanly, e.g. `Insets.base`.
extension SpaceScale on double {
  /// Scaled radius / square dimension.
  double get radius => r;
}
