import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/avatar.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
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
                data: (user) => _AccountCard(
                  name: user.displayName,
                  phone: user.phoneNumber,
                  avatarUrl: user.avatarUrl,
                ),
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

class _AccountCard extends ConsumerStatefulWidget {
  const _AccountCard({required this.name, required this.phone, required this.avatarUrl});

  final String name;
  final String phone;
  final String? avatarUrl;

  @override
  ConsumerState<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends ConsumerState<_AccountCard> {
  bool _busy = false;

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
        children: [
          PressFeedback(
            onTap: _busy ? null : _pickAndUpload,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Avatar(name: widget.name, photoUrl: widget.avatarUrl, size: 84.r),
                Positioned(
                  right: -2.r,
                  bottom: -2.r,
                  child: Container(
                    padding: EdgeInsets.all(Space.xs.w),
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 2),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 14.r,
                            height: 14.r,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: c.onAccent),
                          )
                        : Icon(Icons.camera_alt_outlined, size: 14.r, color: c.onAccent),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: Space.md.h),
          Text(
            widget.name,
            textAlign: TextAlign.center,
            style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2.h),
          Text(widget.phone, textAlign: TextAlign.center, style: context.text.bodySmall),
          SizedBox(height: Space.sm.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PressFeedback(
                onTap: () => _editName(context, ref),
                child: Text(
                  'Edit name',
                  style: context.text.bodySmall?.copyWith(color: c.accent, fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.avatarUrl != null) ...[
                SizedBox(width: Space.sm.w),
                Text('·', style: context.text.bodySmall?.copyWith(color: c.ink3)),
                SizedBox(width: Space.sm.w),
                PressFeedback(
                  onTap: _busy ? null : _remove,
                  child: Text(
                    'Remove photo',
                    style: context.text.bodySmall?.copyWith(color: c.call.solid, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    await showEditNameSheet(context, initialValue: widget.name);
  }

  Future<void> _pickAndUpload() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      await ref
          .read(groupsRepositoryProvider)
          .uploadAvatar(bytes, picked.name, mimeType: picked.mimeType ?? _guessMimeType(picked.name));
      ref.invalidate(currentBackendUserProvider);
      // Every house's member list has its own cached snapshot of this
      // user's avatar_url — invalidating the whole family (not just one
      // groupId) is what makes the new photo show up in every housemates
      // list without waiting for an unrelated member-list event.
      ref.invalidate(groupMembersProvider);
      Haptics.commit();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).removeAvatar();
      ref.invalidate(currentBackendUserProvider);
      ref.invalidate(groupMembersProvider);
      Haptics.commit();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          Row(
            children: [
              for (final option in ThemeMode.values) ...[
                Expanded(
                  child: _ThemeOption(
                    mode: option,
                    selected: mode == option,
                    onTap: () => ref.read(themeControllerProvider.notifier).set(option),
                  ),
                ),
                if (option != ThemeMode.values.last) SizedBox(width: Space.sm.w),
              ],
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
    return PressFeedback(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.state,
        curve: Motion.curve,
        width: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: Space.sm.w, vertical: Space.sm.h),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: selected ? c.accent : c.ink2, size: 18.r),
            SizedBox(height: Space.xs.h),
            Text(
              _label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? c.accent : c.ink2,
                fontWeight: FontWeight.w600,
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
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          PressFeedback(
            onTap: _signingOut ? null : _signOut,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: Space.base.w, vertical: Space.md.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Sign out', style: context.text.bodyLarge?.copyWith(color: c.ink)),
                  ),
                  if (_signingOut)
                    SizedBox(
                      width: 18.r,
                      height: 18.r,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          PressFeedback(
            onTap: _deleting ? null : _confirmDeleteAccount,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: Space.base.w, vertical: Space.md.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Delete account',
                      style: context.text.bodyLarge?.copyWith(color: c.call.solid, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_deleting)
                    SizedBox(
                      width: 18.r,
                      height: 18.r,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.call.solid),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Neither of these providers is autoDispose (see groups_providers.dart) —
  // both cache their last fetch until told otherwise. Without this, signing
  // out and back in as a *different* account in the same app session (the
  // same phone number reused after the previous account was deleted is the
  // sharpest case, but any account switch without fully killing the app
  // hits it) left the new account looking at the previous account's groups
  // and profile until something else happened to invalidate them.
  void _invalidateAccountScopedProviders() {
    ref.invalidate(currentBackendUserProvider);
    ref.invalidate(myGroupsProvider);
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
    ref.read(showSignUpProvider.notifier).state = false;
    _invalidateAccountScopedProviders();
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
      ref.read(showSignUpProvider.notifier).state = false;
      _invalidateAccountScopedProviders();
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

/// [XFile.mimeType] comes back null on some Android gallery pickers, which
/// otherwise left the upload with no content type at all. Falls back to
/// sniffing the file extension picked images always have one of.
String? _guessMimeType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}
