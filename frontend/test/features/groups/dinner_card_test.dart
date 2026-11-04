import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:quietpass/features/groups/dinner_wire.dart';
import 'package:quietpass/features/groups/group_detail_page.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/groups_repository.dart';
import 'package:quietpass/theme/app_theme.dart';

class _MockGroupsRepository extends Mock implements GroupsRepository {}

/// A [PendingNudgesNotifier] that never listens to [groupNudgesProvider] —
/// same reasoning as group_detail_page_entry_cards_test.dart's own copy:
/// the real one keeps a Firebase-backed WebSocket alive, which this test
/// has no Firebase for.
class _FakePendingNudgesNotifier extends PendingNudgesNotifier {
  @override
  List<AppNudge> build(String groupId) => const [];
}

/// Item 7 regression: "Home for dinner" must register exactly the same
/// way "Staying out" does — both chips call setDinnerStatus with their
/// own matching [DinnerStatus] value, and both end up reflected in the
/// refreshed tally. Covers both toggle directions explicitly so a future
/// regression in either one (not just one of them) fails a test.
void main() {
  setUpAll(() {
    // Keeps this test offline and deterministic — without this,
    // AppTheme.light's GoogleFonts.plusJakartaSansTextTheme call tries a
    // real network fetch the first time it runs.
    GoogleFonts.config.allowRuntimeFetching = false;
    // Needed for any(... DinnerStatus) below — mocktail needs some valid
    // instance to stand in for the matcher, never actually inspected.
    registerFallbackValue(DinnerStatus.home);
  });

  const group = AppGroup(id: 'group-1', name: 'Test House', inviteCode: 'ABC123');
  const groupId = 'group-1';
  const me = AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Me');
  const members = [HouseMember(membershipId: 'm1', user: me, role: 'admin')];

  late _MockGroupsRepository repository;
  late DinnerSummary currentSummary;

  DinnerSummary emptySummary() => DinnerSummary(
        day: '2026-01-01',
        cutoffAt: DateTime.now().toUtc(),
        cutoffPassed: false,
        homeCount: 0,
        stayingOutCount: 0,
        responses: const [],
      );

  setUp(() {
    repository = _MockGroupsRepository();
    currentSummary = emptySummary();
    // Stands in for the real backend: records whichever DinnerStatus was
    // actually sent, and makes the next tally refetch reflect it — exactly
    // what dinner_service.set_dinner_status + get_tally do for real,
    // symmetrically for either status.
    when(() => repository.setDinnerStatus(any(), any())).thenAnswer((invocation) async {
      final status = invocation.positionalArguments[1] as DinnerStatus;
      currentSummary = DinnerSummary(
        day: currentSummary.day,
        cutoffAt: currentSummary.cutoffAt,
        cutoffPassed: currentSummary.cutoffPassed,
        homeCount: status == DinnerStatus.home ? 1 : 0,
        stayingOutCount: status == DinnerStatus.stayingOut ? 1 : 0,
        responses: [
          DinnerResponse(userId: me.id, status: status, updatedAt: DateTime.now().toUtc()),
        ],
      );
      return DinnerResponse(userId: me.id, status: status, updatedAt: DateTime.now().toUtc());
    });
  });

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        groupsRepositoryProvider.overrideWith((ref) => repository),
        currentBackendUserProvider.overrideWith((ref) async => me),
        groupMembersProvider(groupId).overrideWith((ref) async => members),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupDinnerSummaryProvider(groupId).overrideWith((ref) async => currentSummary),
        groupDinnerLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupStatusesProvider(groupId).overrideWith((ref) => Stream.value(const <String, MemberStatus>{})),
        groupChoresProvider(groupId).overrideWith((ref) async => const []),
        groupChoresLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupReservationsProvider(groupId).overrideWith((ref) async => const []),
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

  testWidgets('tapping "Home for dinner" sets DinnerStatus.home and updates the tally', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // The dinner card sits below the fold on the test window's default
    // (small) size, same as GroupDetailPage's own scrollable body in a
    // real, shorter viewport.
    await tester.ensureVisible(find.text('Home for dinner'));
    await tester.tap(find.text('Home for dinner'));
    await tester.pumpAndSettle();

    verify(() => repository.setDinnerStatus(groupId, DinnerStatus.home)).called(1);
    expect(find.text('1 home · 0 out'), findsOneWidget);
  });

  testWidgets('tapping "Staying out" sets DinnerStatus.stayingOut and updates the tally', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Staying out'));
    await tester.tap(find.text('Staying out'));
    await tester.pumpAndSettle();

    verify(() => repository.setDinnerStatus(groupId, DinnerStatus.stayingOut)).called(1);
    expect(find.text('0 home · 1 out'), findsOneWidget);
  });
}
