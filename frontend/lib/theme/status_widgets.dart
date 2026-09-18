import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

/// Read-only status badge shown next to a housemate.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final HouseStatus status;

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
            status.label,
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

/// Muted placeholder badge for a member with no live status set.
class NoStatusBadge extends StatelessWidget {
  const NoStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.pill.r),
      ),
      child: Text(
        'No status',
        style: context.text.bodySmall?.copyWith(color: c.ink3),
      ),
    );
  }
}
