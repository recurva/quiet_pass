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

/// One duration preset chip, used in the row shown after picking a status
/// that isn't Open to Chat (which has no duration concept at all).
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
