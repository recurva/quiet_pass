import 'package:flutter/material.dart';

/// Raw color values for QuietPass, one place, never referenced directly by
/// widgets. Screens read semantic tokens from [AppColors] (the ThemeExtension)
/// so the same widget renders correctly in either mode.
///
/// Values are the approved "Teal, dual mode" foundation. Do not hardcode any
/// of these hexes in a widget; add a semantic token instead.
abstract final class DarkPalette {
  static const bg = Color(0xFF0E1116);
  static const surface = Color(0xFF161A21);
  static const surface2 = Color(0xFF1D222B);
  static const surface3 = Color(0xFF232935);

  static const ink = Color(0xFFEDF0F4);
  static const ink2 = Color(0xFFA3ABB9);
  static const ink3 = Color(0xFF6C7480);

  static const line = Color(0xFF252B35);
  static const line2 = Color(0xFF333A47);

  static const accent = Color(0xFF2FB9A9);
  static const accent2 = Color(0xFF46CBBB);
  static const accentPress = Color(0xFF26988B);
  static const onAccent = Color(0xFF0E1116);
  static const accentTint = Color(0x262FB9A9); // ~15% alpha
  static const accentRing = Color(0x662FB9A9); // ~40% alpha

  // Status: solid, tint, ink-on-tint. Solid values are the exact approved
  // per-status hexes (dark mode) from the Time Limits/status-color spec —
  // tint/ink are derived around them, not independently specced.
  static const openSolid = Color(0xFF2FB87A);
  static const openTint = Color(0x242FB87A);
  static const openInk = Color(0xFF7FD3A6);

  static const focusSolid = Color(0xFFE0A23D);
  static const focusTint = Color(0x26E0A23D);
  static const focusInk = Color(0xFFE9C079);

  static const callSolid = Color(0xFFE5564B);
  static const callTint = Color(0x29E5564B);
  static const callInk = Color(0xFFEC9C97);

  static const sleepSolid = Color(0xFF7A7FE0);
  static const sleepTint = Color(0x297A7FE0);
  static const sleepInk = Color(0xFFAAAEF0);

  static const awaySolid = Color(0xFF8A93A3);
  static const awayTint = Color(0x268A93A3);
  static const awayInk = Color(0xFFAEB6C4);
}

abstract final class LightPalette {
  static const bg = Color(0xFFF3F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEDEFF3);
  static const surface3 = Color(0xFFE4E8EE);

  static const ink = Color(0xFF14181F);
  static const ink2 = Color(0xFF565E6B);
  static const ink3 = Color(0xFF8A919E);

  static const line = Color(0xFFE4E7EC);
  static const line2 = Color(0xFFCDD3DB);

  // Teal deepened for light so white button text keeps its contrast.
  static const accent = Color(0xFF12897C);
  static const accent2 = Color(0xFF0F7A6E);
  static const accentPress = Color(0xFF0C6D62);
  static const onAccent = Color(0xFFFFFFFF);
  static const accentTint = Color(0x1A12897C); // ~10% alpha
  static const accentRing = Color(0x4712897C); // ~28% alpha

  static const openSolid = Color(0xFF1E9E63);
  static const openTint = Color(0xFFE4F3EB);
  static const openInk = Color(0xFF1F7A54);

  static const focusSolid = Color(0xFFC9872A);
  static const focusTint = Color(0xFFF8EFD9);
  static const focusInk = Color(0xFF8A6320);

  static const callSolid = Color(0xFFD23F33);
  static const callTint = Color(0xFFFBE7E5);
  static const callInk = Color(0xFF9A3F3A);

  static const sleepSolid = Color(0xFF5B5FD0);
  static const sleepTint = Color(0xFFEAEBF6);
  static const sleepInk = Color(0xFF3F4694);

  static const awaySolid = Color(0xFF6E7684);
  static const awayTint = Color(0xFFECEEF2);
  static const awayInk = Color(0xFF565C66);
}
