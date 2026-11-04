import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';

/// The small "Weekly" pill shown next to a reservation or chore that came
/// from a recurring booking series, rather than a one-off booking. Shared
/// between SpacesPage's reservation rows and ChoresPage's chore rows — both
/// tag the exact same underlying recurring-series concept, so this lives in
/// its own file rather than being duplicated (or owned by just one of the
/// two pages that need it).
class RecurringBadge extends StatelessWidget {
  const RecurringBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Space.sm.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.pill.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5.r, height: 5.r, decoration: BoxDecoration(color: c.ink3, shape: BoxShape.circle)),
          SizedBox(width: 4.w),
          Text(
            'Weekly',
            style: context.text.bodySmall?.copyWith(color: c.ink2, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
