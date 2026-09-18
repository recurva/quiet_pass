import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';

/// Shows the quiet-pulse sheet: pick a duration, see the exact neutral
/// wording that will be sent, confirm. Returns the chosen minutes, or null
/// if dismissed without confirming.
///
/// This is a pure picker — it does not call the backend itself. Sending
/// happens in the caller (group_detail_page) after this sheet has already
/// closed, so a stray tap-outside-to-dismiss (or any other way this sheet's
/// widget gets torn down) can never swallow the send or its error: nothing
/// here has a pending request whose result depends on this widget still
/// being mounted.
Future<int?> showQuietPulseSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QuietPulseSheet(),
  );
}

class _QuietPulseSheet extends StatefulWidget {
  const _QuietPulseSheet();

  @override
  State<_QuietPulseSheet> createState() => _QuietPulseSheetState();
}

class _QuietPulseSheetState extends State<_QuietPulseSheet> {
  int _minutes = 15;

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
            Text('Need it quiet?', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Sent to the whole house. No name attached.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
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
                'A housemate asked for $_minutes minutes of quiet.',
                style: context.text.bodyLarge,
              ),
            ),
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_minutes),
                child: const Text('Send'),
              ),
            ),
          ],
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
