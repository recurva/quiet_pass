import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/chores_page.dart';
import 'package:quietpass/features/groups/group_detail_page.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/housemates_page.dart';
import 'package:quietpass/theme/app_colors.dart';
import 'package:quietpass/theme/app_theme.dart';

/// A [PendingNudgesNotifier] that never listens to [groupNudgesProvider] —
/// the real one keeps a WebSocket ([GroupStatusClient]) alive for as long
/// as the app runs (see that class's own doc comment), which needs a real
/// Firebase-backed [FirebaseAuth] this test has none of. Overriding the
/// notifier itself (rather than something further downstream) is the one
/// place that dependency is actually introduced.
class _FakePendingNudgesNotifier extends PendingNudgesNotifier {
  @override
  List<AppNudge> build(String groupId) => const [];
}

/// Covers item 1's new home layout: Spaces/Housemates/Chores as one
/// consistent row of entry cards grouped under the house header, with
/// Housemates showing a member count + avatar preview and Chores showing
/// how many are due (amber) or "All done" (green) — plus that tapping
/// either one actually opens the right page, now that both have been
/// pulled off this screen's old inline sections.
void main() {
  setUpAll(() {
    // Keeps this test offline and deterministic — without this,
    // AppTheme.light's GoogleFonts.plusJakartaSansTextTheme call tries a
    // real network fetch the first time it runs.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const group = AppGroup(id: 'group-1', name: 'Test House', inviteCode: 'ABC123');
  const groupId = 'group-1';
  const me = AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Me');
  final members = [
    const HouseMember(membershipId: 'm1', user: me, role: 'admin'),
    const HouseMember(
      membershipId: 'm2',
      user: AppUser(id: 'u2', phoneNumber: '+10000000002', displayName: 'Housemate Two'),
      role: 'member',
    ),
    const HouseMember(
      membershipId: 'm3',
      user: AppUser(id: 'u3', phoneNumber: '+10000000003', displayName: 'Housemate Three'),
      role: 'member',
    ),
  ];

  final dinnerSummary = DinnerSummary(
    day: '2026-01-01',
    cutoffAt: DateTime.now().toUtc(),
    cutoffPassed: false,
    homeCount: 0,
    stayingOutCount: 0,
    responses: const [],
  );

  AppChore chore({required String id, required bool done}) => AppChore(
        id: id,
        reservationId: 'r-$id',
        userId: 'u2',
        template: 'Take out the trash',
        dueAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        done: done,
      );

  Widget buildPage(List<AppChore> chores) {
    return ProviderScope(
      overrides: [
        currentBackendUserProvider.overrideWith((ref) async => me),
        groupMembersProvider(groupId).overrideWith((ref) async => members),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupDinnerSummaryProvider(groupId).overrideWith((ref) async => dinnerSummary),
        groupDinnerLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupStatusesProvider(groupId).overrideWith((ref) => Stream.value(const <String, MemberStatus>{})),
        groupChoresProvider(groupId).overrideWith((ref) async => chores),
        groupChoresLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupReservationsProvider(groupId).overrideWith((ref) async => const <AppReservation>[]),
        groupPendingNudgesProvider.overrideWith(_FakePendingNudgesNotifier.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: const GroupDetailPage(group: group),
        ),
      ),
    );
  }

  testWidgets('shows Spaces, Housemates, and Chores as entry cards', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    expect(find.text('Spaces'), findsOneWidget);
    expect(find.text('Housemates'), findsOneWidget);
    expect(find.text('Chores'), findsOneWidget);
  });

  testWidgets('Housemates entry shows the member count', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    expect(find.text('3 members'), findsOneWidget);
  });

  testWidgets('Chores entry shows "N due" in amber when something is due', (tester) async {
    await tester.pumpWidget(buildPage([chore(id: 'c1', done: false)]));
    await tester.pumpAndSettle();

    final dueText = tester.widget<Text>(find.text('1 due'));
    expect(dueText.style?.color, equals(AppTheme.light.extension<AppColors>()!.focus.solid));
  });

  testWidgets('Chores entry shows "All done" in green when nothing is due', (tester) async {
    await tester.pumpWidget(buildPage([chore(id: 'c1', done: true)]));
    await tester.pumpAndSettle();

    final doneText = tester.widget<Text>(find.text('All done'));
    expect(doneText.style?.color, equals(AppTheme.light.extension<AppColors>()!.open.solid));
  });

  testWidgets('tapping the Housemates entry opens HousematesPage', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Housemates'));
    await tester.pumpAndSettle();

    expect(find.byType(HousematesPage), findsOneWidget);
  });

  testWidgets('tapping the Chores entry opens ChoresPage', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();

    expect(find.byType(ChoresPage), findsOneWidget);
  });
}
