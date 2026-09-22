import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import '../push/push_permission_sheet.dart';
import '../push/push_providers.dart';
import 'create_house_sheet.dart';
import 'group_detail_page.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'join_house_sheet.dart';
import 'name_sheet.dart';

/// Lands here right after sign-in: fetches (and provisions, on first call)
/// the backend User, then either lists the caller's houses or prompts them
/// to create or join one.
class GroupsHomePage extends ConsumerStatefulWidget {
  const GroupsHomePage({super.key});

  @override
  ConsumerState<GroupsHomePage> createState() => _GroupsHomePageState();
}

class _GroupsHomePageState extends ConsumerState<GroupsHomePage> {
  bool _promptedThisSession = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = ref.watch(currentBackendUserProvider);
    final groups = ref.watch(myGroupsProvider);

    // Token-refresh + notification-tap wiring runs for the app's whole
    // lifetime once signed in. The permission *prompt* re-shows once per
    // session for as long as it isn't actually granted, and stops for
    // good the moment it is — see _maybePromptForPush for why this isn't
    // narrowed to a "never asked" check (Android can't expose that as a
    // distinct status).
    ref.read(pushClientProvider).start();
    if (!_promptedThisSession && me.hasValue) {
      _promptedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runOnboardingPrompts(me.value!));
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: me.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: friendlyErrorMessage(error),
            onRetry: () {
              ref.invalidate(currentBackendUserProvider);
              ref.invalidate(myGroupsProvider);
            },
          ),
          data: (user) => Padding(
            padding: EdgeInsets.all(Space.base.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Hi, ${user.displayName}', style: context.text.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => _editName(user.displayName),
                      style: IconButton.styleFrom(
                        backgroundColor: c.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.sm.r),
                        ),
                      ),
                      icon: Icon(Icons.edit_outlined, color: c.ink2, size: 18.r),
                    ),
                  ],
                ),
                SizedBox(height: Space.xs.h),
                Text('Your houses', style: context.text.bodySmall),
                SizedBox(height: Space.lg.h),
                Expanded(
                  child: groups.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorState(
                      message: friendlyErrorMessage(error),
                      onRetry: () => ref.invalidate(myGroupsProvider),
                    ),
                    data: (list) =>
                        list.isEmpty ? const _EmptyGroupsState() : _GroupList(groups: list),
                  ),
                ),
                SizedBox(height: Space.base.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => showJoinHouseSheet(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink2,
                          side: BorderSide(color: c.line2),
                          padding: EdgeInsets.symmetric(vertical: Space.md.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.sm.r),
                          ),
                        ),
                        child: const Text('Join a house'),
                      ),
                    ),
                    SizedBox(width: Space.sm.w),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => showCreateHouseSheet(context),
                        child: const Text('Create a house'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runOnboardingPrompts(AppUser user) async {
    // Name capture first (per the Time Limits spec's onboarding
    // requirement), then push permission — sequential, not stacked, so the
    // user only ever sees one sheet at a time.
    await _maybePromptForName(user);
    await _maybePromptForPush();
  }

  Future<void> _maybePromptForName(AppUser user) async {
    if (!mounted) return;
    // The backend defaults display_name to the phone number at first sight
    // (see get_current_user's provisioning) — that equality is exactly how
    // "never customized yet" is detected, with no separate "onboarded" flag
    // needed anywhere.
    if (user.displayName != user.phoneNumber) return;
    await showEditNameSheet(context, initialValue: '', skippable: true);
  }

  Future<void> _editName(String currentName) async {
    final me = ref.read(currentBackendUserProvider).valueOrNull;
    final initial = me != null && me.displayName == me.phoneNumber ? '' : currentName;
    await showEditNameSheet(context, initialValue: initial, skippable: true);
  }

  Future<void> _maybePromptForPush() async {
    if (!mounted) return;
    final status = await ref.read(pushClientProvider).permissionStatus();
    if (!mounted) return;

    // Already granted — just make sure this device's current token is
    // registered, in case it rotated since the last session, and stop.
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      await ref.read(pushClientProvider).registerCurrentToken();
      return;
    }

    // Anything else — notDetermined, or denied — shows the rationale sheet,
    // whose "Allow" calls the real requestPermission(). This is
    // deliberately not narrowed to notDetermined only: Android's
    // checkSelfPermission (what [AuthorizationStatus] is built from on
    // Android) can't distinguish "never asked" from "asked and denied" —
    // both just report denied — so gating on notDetermined meant a fresh
    // install that had never been asked at all went straight to "already
    // decided" and silently skipped the real system dialog entirely. It's
    // safe to always attempt this: Android's own permission API is what
    // decides whether to actually show a dialog or just return the
    // existing decision instantly (once truly permanently denied, calling
    // requestPermission again is a same-frame no-op, not a repeated
    // prompt) — the OS already does the "don't pester the user" job this
    // app doesn't need to duplicate with its own settings-redirect logic.
    await showPushPermissionSheet(context);
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No houses yet',
            style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: Space.xs.h),
          Text(
            'Create one, or join with an invite code.',
            style: context.text.bodySmall?.copyWith(color: c.ink3),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups});

  final List<AppGroup> groups;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => SizedBox(height: Space.sm.h),
      itemBuilder: (context, index) => _GroupTile(group: groups[index]),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final AppGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md.r),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
      ),
      child: Container(
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
              group.name,
              style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: Space.xs.h),
            Text('Invite code: ${group.inviteCode}', style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Space.base.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Something went wrong',
              style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: Space.xs.h),
            Text(
              message,
              style: context.text.bodySmall?.copyWith(color: c.ink3),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: Space.md.h),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink2,
                side: BorderSide(color: c.line2),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
