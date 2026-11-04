import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/agreements_page.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/theme/app_theme.dart';

/// Covers item 3's admin gating: the "Add agreement" FAB on
/// AgreementsPage is driven purely by the [AgreementsPage.isAdmin]
/// constructor flag (set by the caller from the signed-in member's own
/// role), so unlike SpacesPage's equivalent control, this one doesn't
/// need the real member/current-user providers wired up to exercise —
/// only the two providers this page itself reads need overriding.
void main() {
  setUpAll(() {
    // Keeps this test offline and deterministic — without this,
    // AppTheme.light's GoogleFonts.plusJakartaSansTextTheme call tries a
    // real network fetch the first time it runs.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const groupId = 'group-1';

  Widget buildPage({required bool isAdmin}) {
    return ProviderScope(
      overrides: [
        groupAgreementsProvider(groupId).overrideWith((ref) async => const <AppAgreement>[]),
        groupAgreementsLiveRefreshProvider(groupId).overrideWith((ref) {}),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: AgreementsPage(groupId: groupId, groupName: 'Test House', isAdmin: isAdmin),
        ),
      ),
    );
  }

  testWidgets('admin sees the Add agreement button', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: true));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('member does not see the Add agreement button', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
