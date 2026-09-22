import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_x.dart';
import '../groups/groups_home_page.dart';
import 'auth_controller.dart';
import 'phone_entry_page.dart';

/// Root switch between the sign-in flow and the signed-in app, driven by
/// FirebaseAuth's own user stream rather than local navigation state.
/// Lands on [SignInPage] by default — [SignUpPage] is one tap away via
/// its own "New here? Create an account" link.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) => user == null ? const SignInPage() : const GroupsHomePage(),
      loading: () => const _SplashScaffold(),
      error: (_, __) => const SignInPage(),
    );
  }
}

class _SplashScaffold extends StatelessWidget {
  const _SplashScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
