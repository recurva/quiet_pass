import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/local_time.dart';
import '../../theme/app_sheet.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'recurring_badge.dart';

const _weekdayShortLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Shows what actually got booked right after creating a recurring
/// series: a clear summary of the series itself (space, frequency, time
/// — the "what/when" that used to be buried in a one-line stats
/// sentence), then every free occurrence that was booked, and — since
/// this app books the free weeks and reports the rest rather than
/// failing the whole series on one conflict (see the backend's
/// recurring_service.py) — every occurrence that lost to an existing
/// booking, so the person who created the series isn't left guessing
/// which weeks actually landed.
Future<void> showRecurringSeriesResultSheet(
  BuildContext context, {
  required String spaceName,
  required RecurringSeriesCreateResult result,
}) {
  // scrollable: false — this sheet already manages its own internal
  // scrolling for the (possibly long) created/skipped lists via the
  // Flexible + SingleChildScrollView below, while keeping the title,
  // summary, and stats line fixed above it. Wrapping that in
  // showAppSheet's own outer SingleChildScrollView as well would hand
  // that Flexible an unbounded height to flex against, which Flutter
  // can't lay out.
  return showAppSheet<void>(
    context,
    scrollable: false,
    builder: (_) => _RecurringSeriesResultSheet(spaceName: spaceName, result: result),
  );
}

class _RecurringSeriesResultSheet extends StatelessWidget {
  const _RecurringSeriesResultSheet({required this.spaceName, required this.result});

  final String spaceName;
  final RecurringSeriesCreateResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final series = result.series;
    final dayLabels = ([...series.weekdays]..sort()).map((d) => _weekdayShortLabels[d]).join(', ');
    // The series's own hour/minute are UTC; a local hour:minute is shown
    // by combining them with today's date purely for display formatting
    // — same approach SpacesPage's own `_RecurringSeriesRow` uses.
    final sampleUtc = DateTime.now().toUtc();
    final sampleStart = DateTime.utc(
      sampleUtc.year,
      sampleUtc.month,
      sampleUtc.day,
      series.startHourUtc,
      series.startMinuteUtc,
    );
    final sampleEnd = sampleStart.add(Duration(minutes: series.durationMinutes));
    final timeLabel = '${sampleStart.toLocalTimeLabel()} – ${sampleEnd.toLocalTimeLabel()}';

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
            SizedBox(height: Space.lg.h),
            // Series summary: what (space), when (days/time), and
            // frequency (the shared RecurringBadge, same one SpacesPage
            // and ChoresPage use for this exact concept) — one clear
            // block instead of the plain stats sentence this used to
            // open with, which read as cluttered once the created/
            // skipped lists got long.
            _SeriesSummaryCard(spaceName: spaceName, dayLabels: dayLabels, timeLabel: timeLabel),
            SizedBox(height: Space.md.h),
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
                      _SectionLabel(label: 'BOOKED', color: c.ink3),
                      SizedBox(height: Space.sm.h),
                      for (final (reservation, _) in result.created)
                        _OccurrenceRow(
                          dateTimeLabel: reservation.startTime.toLocalDateTimeLabel(),
                          dotColor: c.open.solid,
                        ),
                    ],
                    if (result.skipped.isNotEmpty) ...[
                      SizedBox(height: Space.md.h),
                      _SectionLabel(label: 'SKIPPED — ALREADY BOOKED', color: c.call.solid),
                      SizedBox(height: Space.sm.h),
                      for (final occurrence in result.skipped)
                        _OccurrenceRow(
                          dateTimeLabel: occurrence.startTime.toLocalDateTimeLabel(),
                          dotColor: c.call.solid,
                          subtitle: occurrence.reason,
                          dimmed: true,
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

/// The series's "what/when/frequency" at a glance — same leading-icon +
/// title + badge-row shape SpacesPage's own space cards and recurring
/// rows already use, so this sheet doesn't invent a new visual language
/// for the same information.
class _SeriesSummaryCard extends StatelessWidget {
  const _SeriesSummaryCard({required this.spaceName, required this.dayLabels, required this.timeLabel});

  final String spaceName;
  final String dayLabels;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.md.w),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface3,
              borderRadius: BorderRadius.circular(Radii.sm.r),
            ),
            child: Icon(Icons.meeting_room_outlined, size: 18.r, color: c.ink2),
          ),
          SizedBox(width: Space.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spaceName,
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    const RecurringBadge(),
                    SizedBox(width: Space.sm.w),
                    Expanded(
                      child: Text(
                        '$dayLabels · $timeLabel',
                        style: context.text.bodySmall?.copyWith(color: c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.text.labelLarge?.copyWith(
        color: color,
        fontSize: 11.sp,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// One booked or skipped occurrence — the same "dot marker + Expanded
/// text" list shape AgreementsPage's `_AgreementContent` already uses for
/// a multi-line pinned note, reused here instead of this sheet's old bare
/// [Text] per line. A skipped occurrence also shows [subtitle] (its
/// conflict reason), previously collected by the backend but never
/// actually surfaced here.
class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({
    required this.dateTimeLabel,
    required this.dotColor,
    this.subtitle,
    this.dimmed = false,
  });

  final String dateTimeLabel;
  final Color dotColor;
  final String? subtitle;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: Space.sm.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 7.h),
            child: Container(
              width: 5.r,
              height: 5.r,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          SizedBox(width: Space.sm.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateTimeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(color: dimmed ? c.ink3 : null),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 1.h),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: c.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
