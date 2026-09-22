import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/theme/theme_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // A manually-created container, loaded before runApp, so the persisted
  // theme choice is already in place for the very first frame — passing
  // it into UncontrolledProviderScope keeps it as the one container the
  // whole app tree uses (a fresh ProviderScope() here would create a
  // second, disconnected container).
  final container = ProviderContainer();
  await container.read(themeControllerProvider.notifier).loadInitial();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const QuietPassApp(),
    ),
  );
}
