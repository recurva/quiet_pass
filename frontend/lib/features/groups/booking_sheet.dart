import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';

/// Shows the booking sheet for one space. Returns the booked
/// (AppReservation, AppChore) pair on success, or null if cancelled/failed
/// (the failure itself is already shown inline, via the sheet's own error
/// text — same "don't lose the error to a closed sheet" lesson learned
/// with the quiet-pulse sheet, except here the request happens *inside*
/// the sheet deliberately, because on success we want the sheet itself to
/// hand back the result for the caller to show the chore pass).
Future<(AppReservation, AppChore)?> showBookingSheet(
  BuildContext context, {
  required String groupId,
  required AppSpace space,
}) {
  return showModalBottomSheet<(AppReservation, AppChore)?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BookingSheet(groupId: groupId, space: space),
  );
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.groupId, required this.space});

  final String groupId;
  final AppSpace space;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  late DateTime _startTime;
  int _minutes = 15;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to five minutes from now, so a quick test/booking doesn't
    // require touching the pickers at all.
    _startTime = now.add(const Duration(minutes: 5));
  }

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
            Text('Book ${widget.space.name}', style: context.text.titleLarge),
            SizedBox(height: Space.lg.h),
            Text(
              'STARTS',
              style: context.text.labelLarge?.copyWith(
                color: c.ink3,
                fontSize: 11.sp,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: Space.sm.h),
            GestureDetector(
              onTap: _pickStartTime,
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
                    Text(_startTime.toLocalDateTimeLabel(), style: context.text.bodyLarge),
                    Icon(Icons.edit_calendar_outlined, color: c.ink3, size: 18.r),
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
                      onTap: () => setState(() => _minutes = minutes),
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
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                      )
                    : const Text('Book'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(groupsRepositoryProvider)
          .createReservation(widget.groupId, widget.space.id, _startTime, _minutes);
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
