import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/group_detail_page.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/theme/app_theme.dart';

/// A [PendingNudgesNotifier] that never listens for a real nudge — same
/// reasoning as `group_detail_page_entry_cards_test.dart`'s own copy: the
/// real notifier transitively needs a Firebase-backed `FirebaseAuth` this
/// test has none of.
class _FakeNudgesNotifier extends PendingNudgesNotifier {
  @override
  List<AppNudge> build(String groupId) => const [];
}

/// Covers item 13: the house header's name — GroupDetailPage's
/// [AppGroup.name] next to the QuietPass logo — degrades gracefully for a
/// long house name instead of overflowing. This is literally production
/// data ("Corner House [TESTDATA-a64930]" is the seeded test house's real
/// name), plus an even longer hypothetical name constructed here to push
/// the same case further.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const groupId = 'group-1';
  const me = AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Me');
  final members = [const HouseMember(membershipId: 'm1', user: me, role: 'admin')];

  final dinnerSummary = DinnerSummary(
    day: '2026-01-01',
    cutoffAt: DateTime.now().toUtc(),
    cutoffPassed: false,
    homeCount: 0,
    stayingOutCount: 0,
    responses: const [],
  );

  Widget buildPage(AppGroup group) {
    return ProviderScope(
      overrides: [
        currentBackendUserProvider.overrideWith((ref) async => me),
        groupMembersProvider(groupId).overrideWith((ref) async => members),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupDinnerSummaryProvider(groupId).overrideWith((ref) async => dinnerSummary),
        groupDinnerLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupStatusesProvider(groupId).overrideWith((ref) => Stream.value(const <String, MemberStatus>{})),
        groupChoresProvider(groupId).overrideWith((ref) async => const []),
        groupChoresLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupReservationsProvider(groupId).overrideWith((ref) async => const <AppReservation>[]),
        groupPendingNudgesProvider.overrideWith(_FakeNudgesNotifier.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: GroupDetailPage(group: group),
        ),
      ),
    );
  }

  testWidgets('a long production-shaped house name is a single ellipsized line', (tester) async {
    const group = AppGroup(
      id: groupId,
      name: 'Corner House [TESTDATA-a64930]',
      inviteCode: 'ABC123',
    );
    await tester.pumpWidget(buildPage(group));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(find.text(group.name));
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('an even longer hypothetical house name still lays out with no overflow',
      (tester) async {
    const group = AppGroup(
      id: groupId,
      name: 'The Extremely Long Hypothetical Corner House Name For Overflow Stress Testing '
          '[TESTDATA-a64930]',
      inviteCode: 'ABC123',
    );
    await tester.pumpWidget(buildPage(group));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(find.text(group.name));
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('still lays out with no overflow on a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const group = AppGroup(
      id: groupId,
      name: 'Corner House [TESTDATA-a64930]',
      inviteCode: 'ABC123',
    );
    await tester.pumpWidget(buildPage(group));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
