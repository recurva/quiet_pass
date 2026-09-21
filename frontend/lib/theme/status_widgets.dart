import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/local_time.dart';
import 'app_colors.dart';
import 'dimens.dart';
import 'theme_x.dart';

/// Selectable status chip, shared between the foundation preview and the
/// real group-detail "your status" selector.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final HouseStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.statusOf(status);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: const Cubic(0.2, 0, 0, 1),
        padding:
            EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8.r,
              height: 8.r,
              decoration: BoxDecoration(
                color: selected ? c.onAccent : style.solid,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: Space.sm.w),
            Text(
              status.label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? c.onAccent : c.ink2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only status badge shown next to a housemate. [expiresAt] is the
/// absolute end time from the backend (null for Open to Chat, which never
/// expires) — shown as "until 6:30 PM" so every housemate can see when a
/// status will lapse, the top-priority requirement of the Time Limits spec.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.expiresAt});

  final HouseStatus status;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final style = context.colors.statusOf(status);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: BorderRadius.circular(Radii.pill.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7.r,
            height: 7.r,
            decoration: BoxDecoration(color: style.solid, shape: BoxShape.circle),
          ),
          SizedBox(width: Space.xs.w + 2),
          Text(
            expiresAt == null
                ? status.label
                : '${status.label} · until ${expiresAt!.toLocalTimeLabel()}',
            style: context.text.bodySmall?.copyWith(
              color: style.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single-row duration picker: a slider snapped to [allowedMinutes]'
/// steps, with the currently-selected value shown as text above it — this
/// replaced an earlier one-chip-per-preset row, which read as visual
/// clutter once the scale grew to sixteen 30-minute steps (30m through
/// 8h). [allowedMinutes] must be a non-empty, evenly-ish spaced list;
/// the slider itself only ever deals in the list's *index*, so the actual
/// minute values don't need to be a strict arithmetic sequence.
class DurationSlider extends StatefulWidget {
  const DurationSlider({
    super.key,
    required this.allowedMinutes,
    required this.selectedMinutes,
    required this.formatLabel,
    required this.onChangeEnd,
  });

  final List<int> allowedMinutes;
  final int selectedMinutes;
  final String Function(int minutes) formatLabel;

  /// Fires once, when the drag ends — not on every intermediate step, which
  /// would otherwise mean a network call (setting the status) per pixel
  /// dragged over. Dragging itself only updates this widget's own local
  /// state, so the label and thumb stay smooth without waiting on the
  /// parent to round-trip a request and rebuild.
  final ValueChanged<int> onChangeEnd;

  @override
  State<DurationSlider> createState() => _DurationSliderState();
}

class _DurationSliderState extends State<DurationSlider> {
  late int _dragIndex = _indexOf(widget.selectedMinutes);

  int _indexOf(int minutes) =>
      widget.allowedMinutes.indexOf(minutes).clamp(0, widget.allowedMinutes.length - 1);

  @override
  void didUpdateWidget(DurationSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only follow an external change (e.g. switching to a different
    // status, which resets the default) — never overwrite an in-progress
    // drag with a stale prop.
    if (widget.selectedMinutes != oldWidget.selectedMinutes) {
      _dragIndex = _indexOf(widget.selectedMinutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('For', style: context.text.bodySmall),
            SizedBox(width: Space.xs.w),
            Text(
              widget.formatLabel(widget.allowedMinutes[_dragIndex]),
              style: context.text.bodyLarge?.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: c.accent,
            inactiveTrackColor: c.surface2,
            thumbColor: c.accent,
            overlayColor: c.accentTint,
            trackHeight: 3.r,
          ),
          child: Slider(
            value: _dragIndex.toDouble(),
            min: 0,
            max: (widget.allowedMinutes.length - 1).toDouble(),
            divisions: widget.allowedMinutes.length - 1,
            onChanged: (value) => setState(() => _dragIndex = value.round()),
            onChangeEnd: (value) => widget.onChangeEnd(widget.allowedMinutes[value.round()]),
          ),
        ),
      ],
    );
  }
}

/// One duration preset chip — still used by the quiet-pulse sheet's
/// 15/30/60 min picker, which is short enough that a chip row still reads
/// cleanly (unlike the status duration picker's sixteen steps, above).
class DurationChip extends StatelessWidget {
  const DurationChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: const Cubic(0.2, 0, 0, 1),
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          label,
          style: context.text.labelLarge?.copyWith(
            color: selected ? c.onAccent : c.ink2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
