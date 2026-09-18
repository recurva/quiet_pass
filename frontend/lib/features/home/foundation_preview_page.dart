import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import '../theme/theme_controller.dart';

/// A temporary screen that renders the foundation from real tokens so you can
/// run the project and confirm the theme, both modes, before any product
/// screens exist. It will be replaced by the real home dashboard.
///
/// Everything here reads from `context.colors` and the [Space]/[Radii] scale.
/// No raw hex, no fixed pixel sizes: this doubles as the reference for how
/// every later screen is built.
class FoundationPreviewPage extends ConsumerStatefulWidget {
  const FoundationPreviewPage({super.key});

  @override
  ConsumerState<FoundationPreviewPage> createState() =>
      _FoundationPreviewPageState();
}

class _FoundationPreviewPageState extends ConsumerState<FoundationPreviewPage> {
  HouseStatus _selected = HouseStatus.deepFocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, ref),
              SizedBox(height: Space.lg.h),
              _yourStatusCard(context),
              SizedBox(height: Space.base.h),
              _housematesLabel(context),
              SizedBox(height: Space.sm.h),
              _mate(
                context,
                'Ravi',
                'Bedroom',
                HouseStatus.inCall,
                trailingNote: 'ends ~4:30',
              ),
              SizedBox(height: Space.sm.h),
              _mate(context, 'Meera', 'Living room', HouseStatus.openToChat),
              SizedBox(height: Space.base.h),
              _nudgeCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maple Street', style: context.text.titleLarge),
            SizedBox(height: 2.h),
            Text('4 housemates', style: context.text.bodySmall),
          ],
        ),
        // Quick theme toggle until the settings screen exists.
        IconButton(
          onPressed: () => ref.read(themeControllerProvider.notifier).cycle(),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm.r),
            ),
          ),
          icon: Icon(
            context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: c.ink2,
            size: 20.r,
          ),
        ),
      ],
    );
  }

  Widget _yourStatusCard(BuildContext context) {
    final c = context.colors;
    return _surface(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR STATUS',
            style: context.text.labelLarge?.copyWith(
              color: c.ink3,
              fontSize: 11.sp,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: Space.md.h),
          Wrap(
            spacing: Space.sm.w,
            runSpacing: Space.sm.h,
            children: [
              for (final s in HouseStatus.values)
                StatusChip(
                  status: s,
                  selected: _selected == s,
                  onTap: () => setState(() => _selected = s),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _housematesLabel(BuildContext context) => Text(
        'HOUSEMATES',
        style: context.text.labelLarge?.copyWith(
          color: context.colors.ink3,
          fontSize: 11.sp,
          letterSpacing: 0.5,
        ),
      );

  Widget _mate(
    BuildContext context,
    String name,
    String room,
    HouseStatus status, {
    String? trailingNote,
  }) {
    final c = context.colors;
    final style = c.statusOf(status);
    return _surface(
      context,
      padding: EdgeInsets.symmetric(
        horizontal: Space.md.w,
        vertical: Space.md.h,
      ),
      child: Row(
        children: [
          Container(
            width: 34.r,
            height: 34.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: style.solid, shape: BoxShape.circle),
            child: Text(
              name.characters.take(2).toString().toUpperCase(),
              style: context.text.labelLarge?.copyWith(
                color: c.bg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: Space.md.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: context.text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 1.h),
              Text(room, style: context.text.bodySmall),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(status: status),
              if (trailingNote != null) ...[
                SizedBox(height: Space.xs.h),
                Text(trailingNote, style: context.text.bodySmall),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _nudgeCard(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.all(Space.md.w),
      decoration: BoxDecoration(
        color: c.accentTint,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.accentRing),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need it quiet?',
            style: context.text.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            'Send a neutral request to the house. No name attached.',
            style: context.text.bodySmall,
          ),
          SizedBox(height: Space.md.h),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {},
                  child: const Text('Quiet, 30 min'),
                ),
              ),
              SizedBox(width: Space.sm.w),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.ink2,
                    side: BorderSide(color: c.line2),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.sm.r),
                    ),
                  ),
                  child: const Text('More'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A standard surface card, the base container for most rows and panels.
  Widget _surface(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}
