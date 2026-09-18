import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/app_navigation.dart';
import 'features/auth/auth_gate.dart';
import 'features/theme/theme_controller.dart';
import 'theme/app_theme.dart';

/// Root widget. Sets up the responsive scaler once (design reference 375x812),
/// then hands both themes to [MaterialApp] with the active [ThemeMode] from
/// Riverpod. Every screen below inherits the dual-mode foundation.
class QuietPassApp extends ConsumerWidget {
  const QuietPassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);

    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'QuietPass',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const AuthGate(),
        );
      },
    );
  }
}
