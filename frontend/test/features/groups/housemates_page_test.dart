import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/housemates_page.dart';
import 'package:quietpass/theme/app_theme.dart';

/// Covers the Housemates page pulled off GroupDetailPage: the search field
/// filtering by name, the empty state when a search matches nobody, the
/// admin-only kebab (gated on [HousematesPage.isAdmin], same split
/// AgreementsPage/WifiPage already use for their own admin gating), and
/// that a long seeded test name (see the `[TESTDATA-...]` housemates the
/// real app seeds for "Siri") stays on one ellipsized line instead of
/// overflowing.
void main() {
  setUpAll(() {
    // Keeps this test offline and deterministic — without this,
    // AppTheme.light's GoogleFonts.plusJakartaSansTextTheme call tries a
    // real network fetch the first time it runs.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const groupId = 'group-1';
  const longName = 'Housemate 1 [TESTDATA-a64930]';

  final members = [
    const HouseMember(
      membershipId: 'm1',
      user: AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Alice Admin'),
      role: 'admin',
    ),
    const HouseMember(
      membershipId: 'm2',
      user: AppUser(id: 'u2', phoneNumber: '+10000000002', displayName: longName),
      role: 'member',
    ),
    const HouseMember(
      membershipId: 'm3',
      user: AppUser(id: 'u3', phoneNumber: '+10000000003', displayName: 'Bob Builder'),
      role: 'member',
    ),
  ];

  Widget buildPage({required bool isAdmin, String? myUserId}) {
    return ProviderScope(
      overrides: [
        groupMembersProvider(groupId).overrideWith((ref) async => members),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupStatusesProvider(groupId).overrideWith((ref) => Stream.value(const <String, MemberStatus>{})),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: HousematesPage(
            groupId: groupId,
            groupName: 'Test House',
            isAdmin: isAdmin,
            myUserId: myUserId,
          ),
        ),
      ),
    );
  }

  testWidgets('lists every housemate by default', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false, myUserId: 'u3'));
    await tester.pumpAndSettle();

    expect(find.text('Alice Admin'), findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
  });

  testWidgets('search field filters the list by name as you type', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false, myUserId: 'u3'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pumpAndSettle();

    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('Alice Admin'), findsNothing);
    expect(find.text(longName), findsNothing);
  });

  testWidgets('shows an empty state when the search matches nobody', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false, myUserId: 'u3'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz-nobody-named-this');
    await tester.pumpAndSettle();

    expect(find.textContaining('No housemates match'), findsOneWidget);
    expect(find.text('Bob Builder'), findsNothing);
  });

  testWidgets('a long seeded test name stays on one ellipsized line', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false, myUserId: 'u3'));
    await tester.pumpAndSettle();

    final nameText = tester.widget<Text>(find.text(longName));
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('admin sees the kebab on other members but not on themself', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: true, myUserId: 'u1'));
    await tester.pumpAndSettle();

    // Three members, admin is 'u1' (self) — kebab shows for the other two
    // only ("An admin can manage anyone but themself here", the same rule
    // GroupDetailPage used before this list moved here).
    expect(find.byWidgetPredicate((w) => w is PopupMenuButton), findsNWidgets(2));
  });

  testWidgets('non-admin sees no kebab at all', (tester) async {
    await tester.pumpWidget(buildPage(isAdmin: false, myUserId: 'u3'));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate((w) => w is PopupMenuButton), findsNothing);
  });
}
