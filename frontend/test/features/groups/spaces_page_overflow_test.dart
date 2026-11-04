import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/spaces_page.dart';
import 'package:quietpass/theme/app_theme.dart';

/// A [PendingUrgentAccessRequestsNotifier] seeded with one request up
/// front instead of listening for one — the real notifier's `build`
/// transitively watches [groupStatusClientProvider], which needs a real
/// Firebase-backed `FirebaseAuth` this test has none of (same reasoning
/// `group_detail_page_entry_cards_test.dart`'s own fake nudges notifier
/// documents). Seeding a request here (rather than leaving it empty) also
/// lets this test exercise the urgent-access banner's own long-name
/// wrapping in the same pass.
class _FakeUrgentRequestsNotifier extends PendingUrgentAccessRequestsNotifier {
  @override
  List<UrgentAccessRequest> build(String groupId) => [
        UrgentAccessRequest(
          groupId: groupId,
          spaceId: 'space-1',
          reservationId: 'r1',
          holderId: 'me-id',
          requesterId: 'u2',
          createdAt: DateTime.now().toUtc(),
        ),
      ];
}

/// Covers item 10 (the spaces-screen overflow/clipping audit): every Text
/// widget on SpacesPage that renders dynamic content — the space name, the
/// free/reserved status, a reservation's holder name, a recurring series's
/// space name/day/time summary, and the urgent-access banner's sentence —
/// stays on its intended number of lines with an ellipsis instead of
/// throwing a RenderFlex overflow, even with production-shaped long names:
/// a long seeded space name, a long `[TESTDATA-...]` holder name, and an
/// even longer hypothetical space name constructed here to stress it
/// further.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const groupId = 'group-1';
  const longGroupName = 'Corner House [TESTDATA-a64930] — Extended For Overflow Stress Testing';
  const longSpaceName = 'The Really Long Named Shared Workspace Room';
  const longHolderName = 'Housemate 1 [TESTDATA-a64930]';
  const otherLongHolderName = 'Housemate 2 [TESTDATA-a64930]';

  const me = AppUser(id: 'me-id', phoneNumber: '+10000000001', displayName: 'Me');
  const holder = AppUser(id: 'u2', phoneNumber: '+10000000002', displayName: longHolderName);
  const otherHolder = AppUser(id: 'u3', phoneNumber: '+10000000003', displayName: otherLongHolderName);

  const space = AppSpace(id: 'space-1', groupId: groupId, name: longSpaceName);

  final now = DateTime.now().toUtc();
  final oneOffReservation = AppReservation(
    id: 'r1',
    groupId: groupId,
    spaceId: space.id,
    userId: holder.id,
    startTime: now.add(const Duration(hours: 2)),
    endTime: now.add(const Duration(hours: 3)),
  );
  final seriesReservations = [
    AppReservation(
      id: 'r2',
      groupId: groupId,
      spaceId: space.id,
      userId: otherHolder.id,
      startTime: now.add(const Duration(days: 7, hours: 3)),
      endTime: now.add(const Duration(days: 7, hours: 4)),
      recurringSeriesId: 'series-1',
    ),
    AppReservation(
      id: 'r3',
      groupId: groupId,
      spaceId: space.id,
      userId: otherHolder.id,
      startTime: now.add(const Duration(days: 14, hours: 3)),
      endTime: now.add(const Duration(days: 14, hours: 4)),
      recurringSeriesId: 'series-1',
    ),
  ];

  final mySeries = AppRecurringSeries(
    id: 'series-2',
    groupId: groupId,
    spaceId: space.id,
    userId: me.id,
    weekdays: const [0, 1, 2, 3, 4, 5, 6],
    startHourUtc: 18,
    startMinuteUtc: 30,
    durationMinutes: 60,
    createdAt: now,
  );

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        currentBackendUserProvider.overrideWith((ref) async => me),
        groupSpacesProvider(groupId).overrideWith((ref) async => const [space]),
        groupSpacesLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupReservationsProvider(groupId)
            .overrideWith((ref) async => [oneOffReservation, ...seriesReservations]),
        groupReservationsLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupMembersProvider(groupId).overrideWith(
          (ref) async => [
            const HouseMember(membershipId: 'm1', user: me, role: 'admin'),
            const HouseMember(membershipId: 'm2', user: holder, role: 'member'),
            const HouseMember(membershipId: 'm3', user: otherHolder, role: 'member'),
          ],
        ),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupMyRecurringSeriesProvider(groupId).overrideWith((ref) async => [mySeries]),
        groupMyRecurringSeriesLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupPendingUrgentAccessRequestsProvider.overrideWith(_FakeUrgentRequestsNotifier.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: const SpacesPage(groupId: groupId, groupName: longGroupName),
        ),
      ),
    );
  }

  testWidgets('renders every long-name scenario with no overflow exception', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(longSpaceName), findsWidgets);
    expect(find.textContaining(longHolderName), findsWidgets);
  });

  testWidgets('the group-name subtitle in the header is a single ellipsized line', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final subtitle = tester.widget<Text>(find.text(longGroupName));
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });

  testWidgets('the space-name header text is a single ellipsized line', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final nameText = tester.widget<Text>(find.text(longSpaceName).first);
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a reservation holder name + time stays on one ellipsized line', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // Excludes the urgent-access banner sentence, which also mentions
    // this same holder name (as the requester) but is deliberately
    // allowed up to 2 lines — see the banner-specific test below.
    final rowTextFinder = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains(longHolderName) ?? false) &&
          !(w.data?.contains('needs') ?? false),
    );
    expect(rowTextFinder, findsWidgets);
    for (final element in rowTextFinder.evaluate()) {
      final text = element.widget as Text;
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('the urgent-access banner sentence is capped and ellipsized, not unbounded',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final bannerFinder = find.byWidgetPredicate(
      (w) => w is Text && (w.data?.contains('needs') ?? false) && (w.data?.contains('minutes') ?? false),
    );
    expect(bannerFinder, findsOneWidget);
    final bannerText = tester.widget<Text>(bannerFinder);
    expect(bannerText.maxLines, isNotNull);
    expect(bannerText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a very narrow viewport still lays out with no overflow exception', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
