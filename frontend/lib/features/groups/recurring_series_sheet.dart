import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/theme_x.dart';

/// What [showRecurringSeriesSheet] hands back: weekdays in the backend's
/// own 0=Monday..6=Sunday convention (already converted from whatever
/// local weekday the user actually tapped — see [_RecurringSeriesSheetState._submit]),
/// plus the UTC hour/minute and duration to send as-is.
class RecurringSeriesInput {
  const RecurringSeriesInput({
    required this.weekdaysUtc,
    required this.startHourUtc,
    required this.startMinuteUtc,
    required this.durationMinutes,
  });

  final List<int> weekdaysUtc;
  final int startHourUtc;
  final int startMinuteUtc;
  final int durationMinutes;
}

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Shows the recurring-booking sheet: pick weekdays and a time-of-day,
/// both in the device's own local time for natural picking — converted to
/// the backend's UTC weekday/hour/minute only at submit time. Returns
/// null if dismissed without confirming.
Future<RecurringSeriesInput?> showRecurringSeriesSheet(BuildContext context, {required String spaceName}) {
  return showModalBottomSheet<RecurringSeriesInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecurringSeriesSheet(spaceName: spaceName),
  );
}

class _RecurringSeriesSheet extends StatefulWidget {
  const _RecurringSeriesSheet({required this.spaceName});

  final String spaceName;

  @override
  State<_RecurringSeriesSheet> createState() => _RecurringSeriesSheetState();
}

class _RecurringSeriesSheetState extends State<_RecurringSeriesSheet> {
  // 0=Monday .. 6=Sunday, in the device's own local calendar — converted
  // to UTC weekdays only at submit time.
  final Set<int> _selectedLocalWeekdays = {};
  TimeOfDay _localTime = const TimeOfDay(hour: 19, minute: 0);
  int _minutes = 60;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.base.w,
        right: Space.base.w,
        top: Space.base.h,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.base.h,
      ),
      child: Container(
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
            Text('Book ${widget.spaceName} weekly', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Repeats every week on the days you pick, for up to 8 weeks ahead.',
              style: context.text.bodySmall?.copyWith(color: c.ink3),
            ),
            SizedBox(height: Space.lg.h),
            Text(
              'DAYS',
              style: context.text.labelLarge?.copyWith(
                color: c.ink3,
                fontSize: 11.sp,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: Space.sm.h),
            Wrap(
              spacing: Space.sm.w,
              runSpacing: Space.sm.h,
              children: [
                for (var day = 0; day < 7; day++)
                  _WeekdayChip(
                    label: _weekdayLabels[day],
                    selected: _selectedLocalWeekdays.contains(day),
                    onTap: () {
                      Haptics.selection();
                      setState(() {
                        if (!_selectedLocalWeekdays.remove(day)) _selectedLocalWeekdays.add(day);
                      });
                    },
                  ),
              ],
            ),
            SizedBox(height: Space.lg.h),
            Text(
              'STARTS AT',
              style: context.text.labelLarge?.copyWith(
                color: c.ink3,
                fontSize: 11.sp,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: Space.sm.h),
            PressFeedback(
              onTap: _pickTime,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.md.r),
                  border: Border.all(color: c.line2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_localTime.format(context), style: context.text.bodyLarge),
                    Icon(Icons.access_time, color: c.ink3, size: 18.r),
                  ],
                ),
              ),
            ),
            SizedBox(height: Space.lg.h),
            Text(
              'DURATION',
              style: context.text.labelLarge?.copyWith(
                color: c.ink3,
                fontSize: 11.sp,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: Space.sm.h),
            Row(
              children: [
                for (final minutes in const [15, 30, 60]) ...[
                  Expanded(
                    child: _DurationOption(
                      minutes: minutes,
                      selected: _minutes == minutes,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _minutes = minutes);
                      },
                    ),
                  ),
                  if (minutes != 60) SizedBox(width: Space.sm.w),
                ],
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: Space.sm.h),
              Text(_error!, style: context.text.bodySmall?.copyWith(color: c.call.solid)),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _submit, child: const Text('Create series')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _localTime);
    if (time == null || !mounted) return;
    setState(() => _localTime = time);
  }

  /// For a given local weekday (0=Mon..6=Sun), finds the next date on or
  /// after today whose *local* weekday matches, combines it with the
  /// picked local time, and converts to UTC — the UTC weekday and
  /// hour/minute of that instant are what the backend actually needs. A
  /// local time near midnight can land on a different UTC calendar day
  /// than the local one; converting per-weekday like this (rather than
  /// applying one flat UTC offset to every selection) gets that right
  /// without hardcoding a fixed offset.
  (int weekdayUtc, int hourUtc, int minuteUtc) _toUtc(int localWeekday) {
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day, _localTime.hour, _localTime.minute);
    // DateTime.weekday: Monday=1..Sunday=7 → our convention 0=Mon..6=Sun.
    while ((date.weekday - 1) % 7 != localWeekday) {
      date = date.add(const Duration(days: 1));
    }
    final utc = date.toUtc();
    return ((utc.weekday - 1) % 7, utc.hour, utc.minute);
  }

  void _submit() {
    if (_selectedLocalWeekdays.isEmpty) {
      setState(() => _error = 'Pick at least one day.');
      return;
    }

    // All selections must agree on the resulting UTC hour/minute — they
    // will, since the same local time-of-day is used for every day and
    // this app's single-timezone (IST) assumption means the UTC offset
    // doesn't vary by day of week (see dinner_service.py's own IST
    // comment for the same reasoning applied elsewhere in this app).
    final converted = _selectedLocalWeekdays.map(_toUtc).toList();
    final weekdaysUtc = converted.map((c) => c.$1).toSet().toList()..sort();
    final (_, hourUtc, minuteUtc) = converted.first;

    Navigator.of(context).pop(
      RecurringSeriesInput(
        weekdaysUtc: weekdaysUtc,
        startHourUtc: hourUtc,
        startMinuteUtc: minuteUtc,
        durationMinutes: _minutes,
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.state,
        curve: Motion.curve,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          label,
          style: context.text.labelLarge?.copyWith(
            color: selected ? c.onAccent : c.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DurationOption extends StatelessWidget {
  const _DurationOption({required this.minutes, required this.selected, required this.onTap});

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.state,
        curve: Motion.curve,
        padding: EdgeInsets.symmetric(vertical: Space.sm.h),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          '$minutes min',
          style: context.text.labelLarge?.copyWith(
            color: selected ? c.onAccent : c.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
