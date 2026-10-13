import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/local_time.dart';
import '../../theme/app_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import 'house_status_wire.dart';

/// Shows the status picker sheet: choose a status and, for the four timed
/// ones, how long. Returns the chosen (status, minutes) pair, or null if
/// dismissed without confirming — [minutes] is always null for Open to Chat
/// (no duration concept) and always non-null for every other status.
///
/// A pure picker, same shape as showQuietPulseSheet/showCustomNudgeSheet:
/// it never calls the backend itself. The actual `setMyStatus` call still
/// happens in the caller (group_detail_page's `_setStatus`), unchanged,
/// after this sheet has already closed.
Future<(HouseStatus, int?)?> showStatusPickerSheet(
  BuildContext context, {
  required HouseStatus current,
  required int? currentDurationMinutes,
}) {
  return showModalBottomSheet<(HouseStatus, int?)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StatusPickerSheet(
      initialStatus: current,
      initialDurationMinutes: currentDurationMinutes,
    ),
  );
}

class _StatusPickerSheet extends StatefulWidget {
  const _StatusPickerSheet({required this.initialStatus, required this.initialDurationMinutes});

  final HouseStatus initialStatus;
  final int? initialDurationMinutes;

  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  late HouseStatus _status = widget.initialStatus;
  late int _minutes = widget.initialDurationMinutes ??
      statusDurationRules[widget.initialStatus]?.defaultMinutes ??
      30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rule = statusDurationRules[_status];
    final endTime = DateTime.now().add(Duration(minutes: rule == null ? 0 : _minutes));

    return Padding(
      padding: EdgeInsets.only(
        left: Space.base.w,
        right: Space.base.w,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.base.h,
      ),
      child: Container(
        padding: EdgeInsets.all(Space.base.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg.r)),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: Space.xl.w,
                height: Space.xs.h,
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(Radii.pill.r),
                ),
              ),
            ),
            SizedBox(height: Space.md.h),
            Text('Set your status', style: context.text.titleLarge),
            SizedBox(height: Space.md.h),
            for (final status in HouseStatus.values) ...[
              _StatusOptionRow(
                status: status,
                selected: _status == status,
                onTap: () {
                  Haptics.selection();
                  setState(() {
                    _status = status;
                    final newRule = statusDurationRules[status];
                    if (newRule != null && !newRule.allowedMinutes.contains(_minutes)) {
                      _minutes = newRule.defaultMinutes;
                    }
                  });
                },
              ),
              if (status != HouseStatus.values.last) SizedBox(height: Space.sm.h),
            ],
            if (rule != null) ...[
              SizedBox(height: Space.lg.h),
              Text(
                'FOR HOW LONG',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              DurationSlider(
                allowedMinutes: rule.allowedMinutes,
                selectedMinutes: _minutes,
                formatLabel: formatDurationMinutes,
                onChangeEnd: (minutes) => setState(() => _minutes = minutes),
              ),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Haptics.selection();
                  Navigator.of(context).pop((_status, rule == null ? null : _minutes));
                },
                child: Text(
                  rule == null ? 'Set status' : 'Set · until ${endTime.toLocalTimeLabel()}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single selectable row in the status list: dot + label, with a check
/// mark and accent border/tint when selected. A different shape from the
/// shared [StatusChip] (that one's a compact horizontal pill for the old
/// inline row of five chips) — this is a full-width list row, which is
/// what the sheet's vertical layout calls for.
class _StatusOptionRow extends StatelessWidget {
  const _StatusOptionRow({required this.status, required this.selected, required this.onTap});

  final HouseStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.statusOf(status);
    return PressFeedback(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.state,
        curve: Motion.curve,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Row(
          children: [
            Container(
              width: 10.r,
              height: 10.r,
              decoration: BoxDecoration(color: style.solid, shape: BoxShape.circle),
            ),
            SizedBox(width: Space.sm.w),
            Expanded(
              child: Text(
                status.label,
                style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: c.accent, size: 20.r),
          ],
        ),
      ),
    );
  }
}
