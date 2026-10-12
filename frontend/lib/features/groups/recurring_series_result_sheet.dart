import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/local_time.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';

/// Shows what actually got booked right after creating a recurring
/// series: every free occurrence that was booked, and — since this app
/// books the free weeks and reports the rest rather than failing the
/// whole series on one conflict (see the backend's recurring_service.py)
/// — every occurrence that lost to an existing booking, so the person who
/// created the series isn't left guessing which weeks actually landed.
Future<void> showRecurringSeriesResultSheet(
  BuildContext context, {
  required RecurringSeriesCreateResult result,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecurringSeriesResultSheet(result: result),
  );
}

class _RecurringSeriesResultSheet extends StatelessWidget {
  const _RecurringSeriesResultSheet({required this.result});

  final RecurringSeriesCreateResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.all(Space.base.w),
      child: Container(
        constraints: BoxConstraints(maxHeight: 0.8.sh),
        padding: EdgeInsets.all(Space.base.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg.r),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly booking created', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              '${result.created.length} booked'
              '${result.skipped.isNotEmpty ? ', ${result.skipped.length} skipped' : ''}.',
              style: context.text.bodySmall?.copyWith(color: c.ink3),
            ),
            SizedBox(height: Space.lg.h),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.created.isNotEmpty) ...[
                      Text(
                        'BOOKED',
                        style: context.text.labelLarge?.copyWith(
                          color: c.ink3,
                          fontSize: 11.sp,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: Space.sm.h),
                      for (final (reservation, _) in result.created)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.xs.h),
                          child: Text(
                            reservation.startTime.toLocalDateTimeLabel(),
                            style: context.text.bodyMedium,
                          ),
                        ),
                    ],
                    if (result.skipped.isNotEmpty) ...[
                      SizedBox(height: Space.md.h),
                      Text(
                        'SKIPPED — ALREADY BOOKED',
                        style: context.text.labelLarge?.copyWith(
                          color: c.call.solid,
                          fontSize: 11.sp,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: Space.sm.h),
                      for (final occurrence in result.skipped)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.xs.h),
                          child: Text(
                            occurrence.startTime.toLocalDateTimeLabel(),
                            style: context.text.bodyMedium?.copyWith(color: c.ink3),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
