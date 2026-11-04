import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:quietpass/features/groups/house_tools_sheet.dart';
import 'package:quietpass/theme/app_theme.dart';

/// Regression test for item 1: house_tools_sheet.dart's
/// `showModalBottomSheet` call had no `isScrollControlled`, no scroll
/// view, and no max-height cap, so on a short viewport its content
/// (Agreements + Guest Wi-Fi rows) could clip past the sheet's bottom and
/// right edges — the Guest Wi-Fi row specifically was reported
/// unreachable. Both rows render through [showHouseToolsSheet], now
/// routed through showAppSheet (lib/theme/app_sheet.dart), which this
/// asserts lays out with no overflow and leaves both rows tappable.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpSheetAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showHouseToolsSheet(context),
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

  testWidgets('house tools sheet lays out with no overflow at the 375x812 reference size',
      (tester) async {
    await pumpSheetAt(tester, const Size(375, 812));

    expect(tester.takeException(), isNull);
    expect(find.text('Agreements'), findsOneWidget);
    expect(find.text('Guest Wi-Fi'), findsOneWidget);
  });

  testWidgets('the Guest Wi-Fi row stays reachable and tappable on a short viewport',
      (tester) async {
    // A squat viewport (e.g. a phone in landscape, or a small device) is
    // exactly the shape that clipped the Guest Wi-Fi row before this fix.
    await pumpSheetAt(tester, const Size(375, 480));
    expect(tester.takeException(), isNull);

    final wifiRow = find.text('Guest Wi-Fi');
    expect(wifiRow, findsOneWidget);

    // The sheet's SingleChildScrollView (from showAppSheet) makes this
    // row reachable even when it doesn't fit the available height
    // outright. A genuine tap landing on it pops the sheet with
    // HouseTool.wifi, which this confirms indirectly: the sheet closes
    // (the row's text leaves the tree) only if the real _ToolRow.onTap —
    // not some clipped/unreachable ancestor — actually received the tap.
    await tester.ensureVisible(wifiRow);
    await tester.tap(wifiRow);
    await tester.pumpAndSettle();

    expect(find.text('Guest Wi-Fi'), findsNothing);
  });
}
