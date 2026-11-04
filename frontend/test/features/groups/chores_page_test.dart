import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:quietpass/features/groups/chores_page.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/groups_repository.dart';
import 'package:quietpass/theme/app_theme.dart';

class _MockGroupsRepository extends Mock implements GroupsRepository {}

/// Covers the Chores page pulled off SpacesPage (its old "Yours · Due
/// next" and "Housemates" chore blocks): the caller's own next chore
/// shown as a "chore pass" hero card with Mark done, the friendly empty
/// state when the caller has nothing due, and the house chore rotation
/// (everyone else's pending chores) below it.
void main() {
  setUpAll(() {
    // Keeps this test offline and deterministic — without this,
    // AppTheme.light's GoogleFonts.plusJakartaSansTextTheme call tries a
    // real network fetch the first time it runs.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const groupId = 'group-1';
  const me = AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Me');
  const housemate = HouseMember(
    membershipId: 'm2',
    user: AppUser(id: 'u2', phoneNumber: '+10000000002', displayName: 'Housemate Two'),
    role: 'member',
  );

  late _MockGroupsRepository repository;

  setUp(() {
    repository = _MockGroupsRepository();
    when(() => repository.markChoreDone(any())).thenAnswer((_) async {});
  });

  Widget buildPage(List<AppChore> chores) {
    return ProviderScope(
      overrides: [
        groupsRepositoryProvider.overrideWith((ref) => repository),
        currentBackendUserProvider.overrideWith((ref) async => me),
        groupChoresProvider(groupId).overrideWith((ref) async => chores),
        groupChoresLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupMembersProvider(groupId).overrideWith((ref) async => [housemate]),
        groupMembersLiveRefreshProvider(groupId).overrideWith((ref) {}),
        groupReservationsProvider(groupId).overrideWith((ref) async => const <AppReservation>[]),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: const ChoresPage(groupId: groupId, groupName: 'Test House'),
        ),
      ),
    );
  }

  AppChore chore({required String id, required String userId, required bool done, DateTime? dueAt}) {
    return AppChore(
      id: id,
      reservationId: 'r-$id',
      userId: userId,
      template: 'Wipe down the kitchen',
      dueAt: dueAt ?? DateTime.now().toUtc().add(const Duration(hours: 2)),
      done: done,
    );
  }

  testWidgets('shows a chore pass hero card for the caller\'s own due chore', (tester) async {
    await tester.pumpWidget(buildPage([chore(id: 'c1', userId: 'u1', done: false)]));
    await tester.pumpAndSettle();

    // Appears twice by design: once as this section's own header, once
    // as the hero card's internal label (see _YourNextChoreCard).
    expect(find.text('YOUR CHORE PASS'), findsNWidgets(2));
    expect(find.text('Wipe down the kitchen'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, 'Mark done'), findsOneWidget);
  });

  testWidgets('tapping Mark done calls markChoreDone and clears the hero card', (tester) async {
    await tester.pumpWidget(buildPage([chore(id: 'c1', userId: 'u1', done: false)]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Mark done'));
    await tester.pumpAndSettle();

    verify(() => repository.markChoreDone('c1')).called(1);
  });

  testWidgets('shows a friendly empty state when the caller has nothing due', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mark done'), findsNothing);
  });

  testWidgets('shows the house chore rotation for other housemates', (tester) async {
    await tester.pumpWidget(buildPage([chore(id: 'c2', userId: 'u2', done: false)]));
    await tester.pumpAndSettle();

    expect(find.text('HOUSE CHORE ROTATION'), findsOneWidget);
    expect(find.textContaining('Housemate Two'), findsOneWidget);
    expect(find.text('1 left'), findsOneWidget);
  });

  testWidgets('shows a friendly rotation empty state when nobody else has anything pending', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pumpAndSettle();

    expect(find.text('Nothing pending for anyone else.'), findsOneWidget);
  });
}
