import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the app's [ThemeMode]. Defaults to [ThemeMode.system] so QuietPass
/// follows the phone's setting, with a manual override exposed in settings.
///
/// Persistence (remembering the user's manual choice across launches) is
/// deliberately not wired yet; it will be added with the settings feature so we
/// do not couple the theme layer to a storage choice prematurely.
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;

  /// Cycles system -> light -> dark -> system. Handy for a quick toggle before
  /// the full settings screen exists.
  void cycle() {
    state = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
