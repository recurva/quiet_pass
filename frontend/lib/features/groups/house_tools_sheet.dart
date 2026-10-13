import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';

/// Home for occasional, set-and-forget house actions — today just
/// Agreements and Guest Wi-Fi, but the row list is built to grow: a future
/// occasional feature is one more [_ToolRow] in [rows], never a new pill
/// on the main group detail screen. Same bottom-sheet container style as
/// GroupDetailPage's own confirm/leave sheet, reused rather than
/// reinvented.
enum HouseTool { agreements, wifi }

Future<HouseTool?> showHouseToolsSheet(BuildContext context) {
  return showModalBottomSheet<HouseTool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _HouseToolsSheet(),
  );
}

class _HouseToolsSheet extends StatelessWidget {
  const _HouseToolsSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.all(Space.base.w),
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
            Text('House tools', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Occasional, set-and-forget stuff for this house.',
              style: context.text.bodySmall?.copyWith(color: c.ink3),
            ),
            SizedBox(height: Space.lg.h),
            _ToolRow(
              icon: Icons.push_pin_outlined,
              label: 'Agreements',
              onTap: () => Navigator.of(context).pop(HouseTool.agreements),
            ),
            SizedBox(height: Space.sm.h),
            _ToolRow(
              icon: Icons.qr_code_rounded,
              label: 'Guest Wi-Fi',
              onTap: () => Navigator.of(context).pop(HouseTool.wifi),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20.r, color: c.ink2),
            SizedBox(width: Space.md.w),
            Expanded(child: Text(label, style: context.text.bodyLarge)),
            Icon(Icons.chevron_right, size: 20.r, color: c.ink3),
          ],
        ),
      ),
    );
  }
}
