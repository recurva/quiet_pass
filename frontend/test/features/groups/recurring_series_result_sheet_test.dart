import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/features/groups/recurring_series_result_sheet.dart';
import 'package:quietpass/theme/app_theme.dart';

/// Covers item 11's redesign of the recurring-series result sheet into a
/// cleaner card: a distinct series-summary block (what/when/frequency,
/// using the shared [RecurringBadge] instead of ad-hoc text) separated
/// from the booked/skipped occurrence list, plus the skipped occurrence's
/// own conflict reason now actually surfacing (previously parsed but
/// never shown). Also exercises the long-space-name overflow case from
/// item 10's audit, since this sheet renders a space name of its own.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const longSpaceName = 'The Really Long Named Shared Workspace Room';
  final now = DateTime.now().toUtc();

  final series = AppRecurringSeries(
    id: 'series-1',
    groupId: 'group-1',
    spaceId: 'space-1',
    userId: 'u1',
    weekdays: const [0, 2, 4],
    startHourUtc: 19,
    startMinuteUtc: 0,
    durationMinutes: 60,
    createdAt: now,
  );

  AppReservation reservation(String id, Duration offset) => AppReservation(
        id: id,
        groupId: 'group-1',
        spaceId: 'space-1',
        userId: 'u1',
        startTime: now.add(offset),
        endTime: now.add(offset + const Duration(hours: 1)),
        recurringSeriesId: series.id,
      );

  AppChore chore(String id, String reservationId) => AppChore(
        id: id,
        reservationId: reservationId,
        userId: 'u1',
        template: 'Clean the space after use',
        dueAt: now.add(const Duration(hours: 2)),
        done: false,
      );

  final result = RecurringSeriesCreateResult(
    series: series,
    created: [
      (reservation('r1', const Duration(days: 1)), chore('c1', 'r1')),
      (reservation('r2', const Duration(days: 8)), chore('c2', 'r2')),
    ],
    skipped: [
      SkippedOccurrence(
        startTime: now.add(const Duration(days: 15)),
        endTime: now.add(const Duration(days: 15, hours: 1)),
        reason: 'Already booked by another housemate',
      ),
    ],
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showRecurringSeriesResultSheet(
                    context,
                    spaceName: longSpaceName,
                    result: result,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a clear series summary with the shared RecurringBadge', (tester) async {
    await pumpSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Weekly booking created'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget); // RecurringBadge's own label
    expect(find.text(longSpaceName), findsOneWidget);
  });

  testWidgets('separates booked and skipped occurrences into their own labeled sections',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('BOOKED'), findsOneWidget);
    expect(find.text('SKIPPED — ALREADY BOOKED'), findsOneWidget);
    expect(find.text('2 booked, 1 skipped.'), findsOneWidget);
  });

  testWidgets('a skipped occurrence shows its own conflict reason', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Already booked by another housemate'), findsOneWidget);
  });

  testWidgets('the long space name in the summary stays on one ellipsized line', (tester) async {
    await pumpSheet(tester);

    final nameText = tester.widget<Text>(find.text(longSpaceName));
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('still lays out with no overflow on a short viewport', (tester) async {
    tester.view.physicalSize = const Size(375, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
  });
}
