import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'push_providers.dart';

/// Shown once, after the user has actually landed somewhere useful (their
/// houses list) — never abruptly on cold launch before they've seen
/// anything the app does. Explains *why* before the OS permission prompt
/// appears, rather than surprising them with a bare system dialog.
Future<void> showPushPermissionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PushPermissionSheet(),
  );
}

class _PushPermissionSheet extends ConsumerWidget {
  const _PushPermissionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Text('Stay in the loop', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Get notified when a housemate sends a nudge, even if '
              'QuietPass is closed or your phone is locked. No names, '
              'just the message.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink2,
                      side: BorderSide(color: c.line2),
                      padding: EdgeInsets.symmetric(vertical: Space.md.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm.r),
                      ),
                    ),
                    child: const Text('Not now'),
                  ),
                ),
                SizedBox(width: Space.sm.w),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _allow(context, ref),
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _allow(BuildContext context, WidgetRef ref) async {
    final client = ref.read(pushClientProvider);
    try {
      final settings = await client.requestPermission();
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) {
        await client.registerCurrentToken();
      }
    } catch (_) {
      // Web needs a VAPID key (unconfigured) to mint an FCM token; push is
      // an Android-first feature here, so a failure on web just means this
      // browser won't get pushes — never worth blocking the sheet on.
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
