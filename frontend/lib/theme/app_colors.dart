import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The five household statuses. The enum is the app-wide source of truth for
/// status identity; colors for the current mode come from [AppColors.statusOf].
enum HouseStatus {
  openToChat('Open to Chat'),
  deepFocus('Deep Focus'),
  inCall('In Call'),
  sleepingEarly('Sleeping Early'),
  away('Away');

  const HouseStatus(this.label);

  /// Human-facing label shown on badges and the selector.
  final String label;
}

/// Resolved colors for a single status in the current mode.
@immutable
class StatusStyle {
  const StatusStyle({
    required this.solid,
    required this.tint,
    required this.ink,
  });

  /// The dot / indicator color.
  final Color solid;

  /// The badge background (translucent on dark, soft tint on light).
  final Color tint;

  /// The label color drawn on [tint].
  final Color ink;

  static StatusStyle lerp(StatusStyle a, StatusStyle b, double t) => StatusStyle(
        solid: Color.lerp(a.solid, b.solid, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
      );
}

/// Semantic color tokens for QuietPass, exposed as a [ThemeExtension] so any
/// widget reads them with `Theme.of(context).extension<AppColors>()!` (or the
/// `context.colors` shortcut in theme_x.dart) and automatically gets the right
/// value for the active mode.
///
/// Widgets never import [DarkPalette] / [LightPalette] directly.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.accent,
    required this.accent2,
    required this.accentPress,
    required this.onAccent,
    required this.accentTint,
    required this.accentRing,
    required this.open,
    required this.focus,
    required this.call,
    required this.sleep,
    required this.awayStatus,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;

  final Color ink;
  final Color ink2;
  final Color ink3;

  final Color line;
  final Color line2;

  final Color accent;
  final Color accent2;
  final Color accentPress;
  final Color onAccent;
  final Color accentTint;
  final Color accentRing;

  final StatusStyle open;
  final StatusStyle focus;
  final StatusStyle call;
  final StatusStyle sleep;
  final StatusStyle awayStatus;

  /// Colors for [status] in the current mode.
  StatusStyle statusOf(HouseStatus status) => switch (status) {
        HouseStatus.openToChat => open,
        HouseStatus.deepFocus => focus,
        HouseStatus.inCall => call,
        HouseStatus.sleepingEarly => sleep,
        HouseStatus.away => awayStatus,
      };

  static const AppColors dark = AppColors(
    bg: DarkPalette.bg,
    surface: DarkPalette.surface,
    surface2: DarkPalette.surface2,
    surface3: DarkPalette.surface3,
    ink: DarkPalette.ink,
    ink2: DarkPalette.ink2,
    ink3: DarkPalette.ink3,
    line: DarkPalette.line,
    line2: DarkPalette.line2,
    accent: DarkPalette.accent,
    accent2: DarkPalette.accent2,
    accentPress: DarkPalette.accentPress,
    onAccent: DarkPalette.onAccent,
    accentTint: DarkPalette.accentTint,
    accentRing: DarkPalette.accentRing,
    open: StatusStyle(
      solid: DarkPalette.openSolid,
      tint: DarkPalette.openTint,
      ink: DarkPalette.openInk,
    ),
    focus: StatusStyle(
      solid: DarkPalette.focusSolid,
      tint: DarkPalette.focusTint,
      ink: DarkPalette.focusInk,
    ),
    call: StatusStyle(
      solid: DarkPalette.callSolid,
      tint: DarkPalette.callTint,
      ink: DarkPalette.callInk,
    ),
    sleep: StatusStyle(
      solid: DarkPalette.sleepSolid,
      tint: DarkPalette.sleepTint,
      ink: DarkPalette.sleepInk,
    ),
    awayStatus: StatusStyle(
      solid: DarkPalette.awaySolid,
      tint: DarkPalette.awayTint,
      ink: DarkPalette.awayInk,
    ),
  );

  static const AppColors light = AppColors(
    bg: LightPalette.bg,
    surface: LightPalette.surface,
    surface2: LightPalette.surface2,
    surface3: LightPalette.surface3,
    ink: LightPalette.ink,
    ink2: LightPalette.ink2,
    ink3: LightPalette.ink3,
    line: LightPalette.line,
    line2: LightPalette.line2,
    accent: LightPalette.accent,
    accent2: LightPalette.accent2,
    accentPress: LightPalette.accentPress,
    onAccent: LightPalette.onAccent,
    accentTint: LightPalette.accentTint,
    accentRing: LightPalette.accentRing,
    open: StatusStyle(
      solid: LightPalette.openSolid,
      tint: LightPalette.openTint,
      ink: LightPalette.openInk,
    ),
    focus: StatusStyle(
      solid: LightPalette.focusSolid,
      tint: LightPalette.focusTint,
      ink: LightPalette.focusInk,
    ),
    call: StatusStyle(
      solid: LightPalette.callSolid,
      tint: LightPalette.callTint,
      ink: LightPalette.callInk,
    ),
    sleep: StatusStyle(
      solid: LightPalette.sleepSolid,
      tint: LightPalette.sleepTint,
      ink: LightPalette.sleepInk,
    ),
    awayStatus: StatusStyle(
      solid: LightPalette.awaySolid,
      tint: LightPalette.awayTint,
      ink: LightPalette.awayInk,
    ),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? line,
    Color? line2,
    Color? accent,
    Color? accent2,
    Color? accentPress,
    Color? onAccent,
    Color? accentTint,
    Color? accentRing,
    StatusStyle? open,
    StatusStyle? focus,
    StatusStyle? call,
    StatusStyle? sleep,
    StatusStyle? awayStatus,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accentPress: accentPress ?? this.accentPress,
      onAccent: onAccent ?? this.onAccent,
      accentTint: accentTint ?? this.accentTint,
      accentRing: accentRing ?? this.accentRing,
      open: open ?? this.open,
      focus: focus ?? this.focus,
      call: call ?? this.call,
      sleep: sleep ?? this.sleep,
      awayStatus: awayStatus ?? this.awayStatus,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentPress: Color.lerp(accentPress, other.accentPress, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      accentRing: Color.lerp(accentRing, other.accentRing, t)!,
      open: StatusStyle.lerp(open, other.open, t),
      focus: StatusStyle.lerp(focus, other.focus, t),
      call: StatusStyle.lerp(call, other.call, t),
      sleep: StatusStyle.lerp(sleep, other.sleep, t),
      awayStatus: StatusStyle.lerp(awayStatus, other.awayStatus, t),
    );
  }
}
