import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'theme_mode';

/// Holds the app's [ThemeMode]. Defaults to [ThemeMode.system] so QuietPass
/// follows the phone's setting, with a manual override exposed in the
/// profile screen. A manual choice persists across app restarts via
/// [SharedPreferences] — plain, non-secret local storage, unlike the
/// Firebase ID token (which uses flutter_secure_storage instead).
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Called once at startup (see main.dart), before `runApp`, via a
  /// manually-created `ProviderContainer` — `Notifier.build()` itself
  /// can't be async, so this is what makes the persisted choice land
  /// before the very first frame instead of flashing the default and
  /// then jumping to the real saved mode.
  Future<void> loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  /// Cycles system -> light -> dark -> system. Handy for a quick toggle in
  /// the foundation preview page.
  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    set(next);
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
