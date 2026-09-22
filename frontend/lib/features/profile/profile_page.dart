import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import '../auth/auth_controller.dart';
import '../groups/groups_providers.dart';
import '../groups/name_sheet.dart';
import '../theme/theme_controller.dart';

/// Reached from the home screen's settings icon. Shows the caller's name
/// and phone number, lets them edit their name, pick a theme, sign out,
/// or delete their account.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(currentBackendUserProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              SizedBox(height: Space.lg.h),
              me.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(
                  friendlyErrorMessage(error),
                  style: context.text.bodySmall?.copyWith(color: c.ink3),
                ),
                data: (user) => _AccountCard(name: user.displayName, phone: user.phoneNumber),
              ),
              SizedBox(height: Space.base.h),
              const _ThemeCard(),
              SizedBox(height: Space.base.h),
              const _AccountActionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
          ),
          icon: Icon(Icons.arrow_back, color: c.ink2, size: 20.r),
        ),
        SizedBox(width: Space.md.w),
        Text('Profile', style: context.text.titleLarge),
      ],
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2.h),
                    Text(phone, style: context.text.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editName(context, ref),
                style: IconButton.styleFrom(
                  backgroundColor: c.surface2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                ),
                icon: Icon(Icons.edit_outlined, color: c.ink2, size: 18.r),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    await showEditNameSheet(context, initialValue: name);
  }
}

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeControllerProvider);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APPEARANCE',
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
              for (final option in ThemeMode.values)
                _ThemeOption(
                  mode: option,
                  selected: mode == option,
                  onTap: () => ref.read(themeControllerProvider.notifier).set(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.mode, required this.selected, required this.onTap});

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  IconData get _icon => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: const Cubic(0.2, 0, 0, 1),
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: selected ? c.onAccent : c.ink2, size: 16.r),
            SizedBox(width: Space.xs.w),
            Text(
              _label,
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

class _AccountActionsCard extends ConsumerStatefulWidget {
  const _AccountActionsCard();

  @override
  ConsumerState<_AccountActionsCard> createState() => _AccountActionsCardState();
}

class _AccountActionsCardState extends ConsumerState<_AccountActionsCard> {
  bool _signingOut = false;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _signingOut ? null : _signOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink2,
                side: BorderSide(color: c.line2),
                padding: EdgeInsets.symmetric(vertical: Space.md.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
              ),
              child: _signingOut
                  ? SizedBox(
                      width: 18.r,
                      height: 18.r,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                    )
                  : const Text('Sign out'),
            ),
          ),
          SizedBox(height: Space.sm.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _deleting ? null : _confirmDeleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.call.solid,
                side: BorderSide(color: c.call.solid),
                padding: EdgeInsets.symmetric(vertical: Space.md.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
              ),
              child: _deleting
                  ? SizedBox(
                      width: 18.r,
                      height: 18.r,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.call.solid),
                    )
                  : const Text('Delete account'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    // Pop back to the root route *before* signing out: AuthGate swaps what
    // it renders reactively the moment FirebaseAuth's user stream fires,
    // but it doesn't touch the Navigator stack above it — anything pushed
    // on top (this profile screen included) would otherwise stay visible,
    // covering the phone-entry screen that just appeared underneath.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(firebaseAuthProvider).signOut();
    await ref.read(authTokenStoreProvider).clear();
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await _showDeleteConfirmSheet(context);
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(groupsRepositoryProvider).deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      await ref.read(firebaseAuthProvider).signOut();
      await ref.read(authTokenStoreProvider).clear();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool?> _showDeleteConfirmSheet(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _DeleteAccountConfirmSheet(),
    );
  }
}

class _DeleteAccountConfirmSheet extends StatelessWidget {
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
            Text('Delete your account?', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'This permanently removes your account, house memberships, '
              'reservations, and chores. This can\'t be undone.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink2,
                      side: BorderSide(color: c.line2),
                      padding: EdgeInsets.symmetric(vertical: Space.md.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm.r),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(width: Space.sm.w),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: c.call.solid),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
