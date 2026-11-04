import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/booking_sheet.dart';
import 'package:quietpass/features/groups/group_models.dart';
import 'package:quietpass/theme/app_theme.dart';

/// Regression test for item 1: booking_sheet.dart already set
/// `isScrollControlled: true`, but had nothing to scroll and no height
/// cap if its DURATION/START TIME cards plus the confirm button didn't
/// fit — reported as overflowing "by 302 pixels on the bottom," clipping
/// the Start Time selector and the confirm button so a booking couldn't
/// be completed at all. Both the scroll/height-cap fix (showAppSheet) and
/// the DURATION/START TIME label text-scale clamp are covered here.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const space = AppSpace(id: 's1', groupId: 'g1', name: 'Kitchen');

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size surfaceSize = const Size(375, 812),
    double textScale = 1.0,
  }) async {
    // Sets the *logical* test viewport to exactly [surfaceSize] — the
    // test binding's view defaults to a devicePixelRatio other than 1.0,
    // so setting `physicalSize` alone (or via `tester.binding.
    // setSurfaceSize`, which sets physical size too) would leave the
    // actual logical size (physicalSize / devicePixelRatio) smaller than
    // intended, making every ScreenUtil `.w`/`.h`/`.r` scale down far
    // more than a real 375x812 device ever would and producing a false
    // overflow that doesn't reflect anything this fix is meant to catch.
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => showBookingSheet(context, groupId: 'g1', space: space),
                      child: const Text('open'),
                    ),
                  ),
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

  testWidgets('booking sheet lays out with no overflow at the 375x812 reference size',
      (tester) async {
    await pumpSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('START TIME'), findsOneWidget);

    // The confirm button must be present and enabled (not clipped out,
    // not disabled) — this is the control the client reported as
    // unreachable.
    final confirmButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(confirmButton.onPressed, isNotNull);
  });

  testWidgets('booking sheet still fits with a large OS text-scale setting', (tester) async {
    await pumpSheet(tester, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('START TIME'), findsOneWidget);
  });

  testWidgets('booking sheet still fits on a short viewport', (tester) async {
    await pumpSheet(tester, surfaceSize: const Size(375, 560));

    expect(tester.takeException(), isNull);
    final confirmButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(confirmButton.onPressed, isNotNull);
  });
}
