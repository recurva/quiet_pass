import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/groups_providers.dart';
import 'package:quietpass/features/groups/groups_repository.dart';
import 'package:quietpass/features/profile/profile_page.dart';
import 'package:quietpass/theme/app_theme.dart';

class _MockGroupsRepository extends Mock implements GroupsRepository {}

/// Covers item 12: "Remove photo" moved into the same photo-source sheet
/// as "Take a photo"/"Choose from library" (instead of the old plain
/// text link next to "Edit name"), only offered when the caller actually
/// has a photo set, and gated behind a confirm step before anything is
/// actually removed — matching the Cancel/destructive-FilledButton
/// confirm shape this app already uses for removing a space or a
/// housemate.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const withPhoto = AppUser(
    id: 'u1',
    phoneNumber: '+10000000001',
    displayName: 'Me',
    avatarUrl: 'https://example.com/avatar.png',
  );
  const withoutPhoto = AppUser(id: 'u1', phoneNumber: '+10000000001', displayName: 'Me');

  late _MockGroupsRepository repository;

  setUp(() {
    repository = _MockGroupsRepository();
    when(() => repository.removeAvatar()).thenAnswer((_) async {});
  });

  Widget buildPage(AppUser user) {
    return ProviderScope(
      overrides: [
        groupsRepositoryProvider.overrideWith((ref) => repository),
        currentBackendUserProvider.overrideWith((ref) async => user),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: const ProfilePage(),
        ),
      ),
    );
  }

  testWidgets('a caller with a photo sees "Remove photo" in the photo-source sheet',
      (tester) async {
    await tester.pumpWidget(buildPage(withPhoto));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Stack).first);
    await tester.pumpAndSettle();

    expect(find.text('Update photo'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from library'), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
  });

  testWidgets('a caller with no photo never sees "Remove photo"', (tester) async {
    await tester.pumpWidget(buildPage(withoutPhoto));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Stack).first);
    await tester.pumpAndSettle();

    expect(find.text('Update photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('tapping Remove photo asks for confirmation before removing anything',
      (tester) async {
    await tester.pumpWidget(buildPage(withPhoto));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Stack).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    // The photo-source sheet is gone, replaced by a confirm step — and
    // nothing has been removed yet.
    expect(find.text('Remove your photo?'), findsOneWidget);
    verifyNever(() => repository.removeAvatar());

    // Cancelling the confirm step still removes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.removeAvatar());
  });

  testWidgets('confirming actually removes the photo', (tester) async {
    await tester.pumpWidget(buildPage(withPhoto));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Stack).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    verify(() => repository.removeAvatar()).called(1);
  });
}
