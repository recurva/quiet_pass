import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';

/// Mirrors the backend's `reservation_buffer_minutes` (app/core/config.py)
/// — the gap the server's EXCLUDE constraint already enforces between any
/// two bookings on the same space. Used here only to warn the user about
/// an overlap *before* they submit; the server-side constraint is still
/// the actual source of truth (see [_BookingSheetState._overlaps]'s doc
/// comment), so this only ever needs to stay roughly in sync, not exactly.
const reservationBufferMinutes = 15;

/// Shows the booking sheet for one space. Returns the booked
/// (AppReservation, AppChore) pair on success, or null if cancelled/failed
/// (the failure itself is already shown inline, via the sheet's own error
/// text — same "don't lose the error to a closed sheet" lesson learned
/// with the quiet-pulse sheet, except here the request happens *inside*
/// the sheet deliberately, because on success we want the sheet itself to
/// hand back the result for the caller to show the chore pass).
///
/// [existingReservations] is this space's current reservation list (every
/// state: in-use, reserved-later-today, and further out) — used purely to
/// block an overlapping pick client-side before it ever reaches the
/// server; see [_BookingSheetState._overlaps].
Future<(AppReservation, AppChore)?> showBookingSheet(
  BuildContext context, {
  required String groupId,
  required AppSpace space,
  List<AppReservation> existingReservations = const [],
}) {
  return showModalBottomSheet<(AppReservation, AppChore)?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BookingSheet(
      groupId: groupId,
      space: space,
      existingReservations: existingReservations,
    ),
  );
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({
    required this.groupId,
    required this.space,
    required this.existingReservations,
  });

  final String groupId;
  final AppSpace space;
  final List<AppReservation> existingReservations;

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

  /// True if [start, start+minutes) overlaps any existing reservation on
  /// this space once its own buffer is applied — mirroring the server's
  /// `ex_reservations_no_overlap` EXCLUDE constraint (see
  /// reservation_service.py's module docstring: every booking's range is
  /// padded to `[start, end + buffer)` before checking intersection, on
  /// both sides being compared). This is advisory only — a client-side
  /// shortcut to block an obviously-doomed pick before it round-trips to
  /// the server, not a replacement for that constraint, which still has
  /// the final say (and whose rejection is still shown via [_error] if
  /// this check somehow missed something, e.g. a booking made by someone
  /// else in the time between opening this sheet and submitting).
  bool _overlaps(DateTime start, DateTime end) {
    const buffer = Duration(minutes: reservationBufferMinutes);
    for (final r in widget.existingReservations) {
      if (r.startTime.isBefore(end.add(buffer)) && start.isBefore(r.endTime.add(buffer))) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selectedEnd = _startTime.add(Duration(minutes: _minutes));
    final overlapsExisting = _overlaps(_startTime, selectedEnd);

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
            Text('Book', style: context.text.titleLarge),
            SizedBox(height: 2.h),
            Text(widget.space.name, style: context.text.bodySmall?.copyWith(color: c.ink3)),
            SizedBox(height: Space.lg.h),
            _sectionCard(
              context,
              label: 'DURATION',
              child: Row(
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
            ),
            SizedBox(height: Space.md.h),
            _sectionCard(
              context,
              label: 'START TIME',
              child: PressFeedback(
                onTap: _pickStartTime,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
                  decoration: BoxDecoration(
                    color: overlapsExisting ? c.call.tint : c.accentTint,
                    borderRadius: BorderRadius.circular(Radii.md.r),
                    border: Border.all(color: overlapsExisting ? c.call.solid : c.accent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _startTime.toLocalDateTimeLabel(),
                        style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Icon(
                        Icons.edit_calendar_outlined,
                        color: overlapsExisting ? c.call.solid : c.accent,
                        size: 18.r,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (overlapsExisting) ...[
              SizedBox(height: Space.sm.h),
              Text(
                'That overlaps an existing booking on this space (plus a '
                '$reservationBufferMinutes min buffer). Pick another time.',
                style: context.text.bodySmall?.copyWith(color: c.call.solid, fontWeight: FontWeight.w600),
              ),
            ],
            SizedBox(height: Space.md.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Space.md.w),
              decoration: BoxDecoration(
                color: c.accentTint,
                borderRadius: BorderRadius.circular(Radii.md.r),
                border: Border.all(color: c.accentRing),
              ),
              child: Text(
                'A cleanup chore is created automatically for whoever books this, due when the booking ends.',
                style: context.text.bodySmall?.copyWith(color: c.accent),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: Space.sm.h),
              Text(_error!, style: context.text.bodySmall?.copyWith(color: c.call.solid)),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting || overlapsExisting ? null : _submit,
                child: _submitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                      )
                    : Text(
                        'Reserve ${_startTime.toLocalTimeLabel()} – '
                        '${_startTime.add(Duration(minutes: _minutes)).toLocalTimeLabel()}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A labelled sub-card ("DURATION" / "START TIME"), matching the
  /// mockup's grouping of each input into its own card within the sheet.
  Widget _sectionCard(BuildContext context, {required String label, required Widget child}) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.md.w),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelLarge?.copyWith(
              color: c.ink3,
              fontSize: 11.sp,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: Space.sm.h),
          child,
        ],
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
      Haptics.commit();
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
