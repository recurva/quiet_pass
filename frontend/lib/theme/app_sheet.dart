import 'package:flutter/material.dart';

/// Every bottom sheet in this app should be shown through [showAppSheet]
/// instead of calling `showModalBottomSheet` directly.
///
/// This exists because of a real bug class: several sheets
/// (`house_tools_sheet.dart` was missing `isScrollControlled` entirely;
/// `booking_sheet.dart` had it but nothing to scroll if the content still
/// didn't fit) rendered their content with no way to grow past the
/// available height and no way to scroll to the part that didn't fit —
/// on a short viewport, a large OS text-scale setting, or with the
/// keyboard up, the sheet simply clipped its own bottom/right edge and
/// whatever controls lived there became untappable. [showAppSheet] fixes
/// this once, at the root, for every call site:
///  - always `isScrollControlled: true` (the sheet may use the full
///    available height instead of defaulting to ~half);
///  - the content is capped to 90% of the screen height and wrapped in a
///    [SingleChildScrollView], so anything taller than that scrolls
///    instead of overflowing/clipping;
///  - wrapped in a bottom-only [SafeArea], so the device's own bottom
///    inset (home indicator, nav bar) never eats into the content.
///
/// [builder] should return exactly what it would have returned as
/// `showModalBottomSheet`'s own `builder` before — this wraps that
/// content, it doesn't replace it. Callers keep their own
/// Padding/Container/decoration/handle exactly as before.
///
/// Pass [scrollable]: false for a sheet that already manages its own
/// internal scrolling for a variable-length middle section while keeping
/// a header/footer fixed (see `recurring_series_result_sheet.dart`) — an
/// outer [SingleChildScrollView] would give that sheet's `Flexible`
/// region an unbounded height to flex against, which Flutter can't lay
/// out. The height cap and [SafeArea] still apply either way.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final content = builder(sheetContext);
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: scrollable ? SingleChildScrollView(child: content) : content,
        ),
      );
    },
  );
}
