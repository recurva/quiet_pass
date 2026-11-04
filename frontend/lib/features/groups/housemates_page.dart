import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sheet.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/avatar.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';

enum _MemberAction { promote, demote, remove }

/// The full housemates roster, with a live status badge per member and a
/// name search pinned above the list — pulled off GroupDetailPage (the
/// house "home" screen), which used to show every member inline
/// regardless of house size. A seeded test house can have 20+ members
/// with long names (see `[TESTDATA-...]` suffixes), which is exactly the
/// case the search field and the name's single-line ellipsis both exist
/// for.
///
/// [isAdmin] and [myUserId] are passed in from the caller's own already-
/// fetched membership/user, the same split AgreementsPage/WifiPage use for
/// [isAdmin] — this screen doesn't need to re-derive either from
/// [currentBackendUserProvider] itself.
class HousematesPage extends ConsumerStatefulWidget {
  const HousematesPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.isAdmin,
    required this.myUserId,
  });

  final String groupId;
  final String groupName;
  final bool isAdmin;
  final String? myUserId;

  @override
  ConsumerState<HousematesPage> createState() => _HousematesPageState();
}

class _HousematesPageState extends ConsumerState<HousematesPage> {
  final _searchController = TextEditingController();
  String _query = '';

  // Nothing server-side pushes an update at the exact moment a status's
  // TTL lapses (Redis just lets the key expire silently) — this timer is
  // what makes an already-open screen notice the crossover and flip a
  // member's badge to Open to Chat without needing a fresh fetch. Same
  // mechanism GroupDetailPage used before this list moved here.
  Timer? _expiryTick;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _query) setState(() => _query = next);
    });
    _expiryTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _expiryTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now().toUtc();
    final groupId = widget.groupId;

    ref.watch(groupMembersLiveRefreshProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final statusesAsync = ref.watch(groupStatusesProvider(groupId));
    final statuses = statusesAsync.valueOrNull ?? const <String, MemberStatus>{};

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Space.base.w, Space.base.h, Space.base.w, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  SizedBox(height: Space.base.h),
                  _searchField(context),
                  SizedBox(height: Space.sm.h),
                ],
              ),
            ),
            Expanded(
              child: membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorState(
                  message: friendlyErrorMessage(error),
                  onRetry: () => ref.invalidate(groupMembersProvider(groupId)),
                ),
                data: (members) {
                  final query = _query.toLowerCase();
                  final filtered = query.isEmpty
                      ? members
                      : members.where((m) => m.user.displayName.toLowerCase().contains(query)).toList();

                  if (members.isEmpty) {
                    return const _EmptyMembersState();
                  }
                  if (filtered.isEmpty) {
                    return _NoSearchMatchesState(query: _query);
                  }

                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(Space.base.w, 0, Space.base.w, Space.base.h),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => SizedBox(height: Space.sm.h),
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final isMe = widget.myUserId != null && member.user.id == widget.myUserId;
                      return FadeSlideIn(
                        key: ValueKey('member-${member.membershipId}'),
                        child: _MemberCard(
                          member: member,
                          status: statuses[member.user.id],
                          now: now,
                          isMe: isMe,
                          canManage: widget.isAdmin && !isMe,
                          onPromote: () => _promoteMember(member),
                          onDemote: () => _demoteMember(member),
                          onRemove: () => _removeMember(member),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Housemates', style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Text(widget.groupName, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      style: context.text.bodyLarge?.copyWith(color: c.ink),
      decoration: InputDecoration(
        hintText: 'Search housemates',
        hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
        prefixIcon: Icon(Icons.search, size: 20.r, color: c.ink3),
        suffixIcon: _query.isEmpty
            ? null
            : PressFeedback(
                onTap: _searchController.clear,
                child: Icon(Icons.close_rounded, size: 18.r, color: c.ink3),
              ),
        filled: true,
        fillColor: c.surface2,
        contentPadding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md.r),
          borderSide: BorderSide(color: c.line2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md.r),
          borderSide: BorderSide(color: c.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md.r),
          borderSide: BorderSide(color: c.accent),
        ),
      ),
    );
  }

  Future<void> _promoteMember(HouseMember member) async {
    try {
      await ref.read(groupsRepositoryProvider).promoteToAdmin(member.membershipId);
      ref.invalidate(groupMembersProvider(widget.groupId));
      if (mounted) showAppSnackBar(context, '${member.user.displayName} is now an admin.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _demoteMember(HouseMember member) async {
    try {
      await ref.read(groupsRepositoryProvider).demoteToMember(member.membershipId);
      ref.invalidate(groupMembersProvider(widget.groupId));
      if (mounted) {
        showAppSnackBar(context, '${member.user.displayName} is no longer an admin.');
      }
    } on ApiException catch (e) {
      // Covers the backend's 409 ("would leave the house with no admin")
      // the same way every other action-failure here does — the message
      // itself already explains what to do (promote someone else first).
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _removeMember(HouseMember member) async {
    final confirmed = await _showConfirmSheet(
      context,
      title: 'Remove ${member.user.displayName}?',
      body: 'They\'ll be removed from this house immediately.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(groupsRepositoryProvider).removeMembership(member.membershipId);
      ref.invalidate(groupMembersProvider(widget.groupId));
      if (mounted) showAppSnackBar(context, '${member.user.displayName} was removed.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<bool?> _showConfirmSheet(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    final c = context.colors;
    return showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
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
              Text(title, style: context.text.titleLarge),
              SizedBox(height: Space.sm.h),
              Text(body, style: context.text.bodySmall?.copyWith(color: c.ink3)),
              SizedBox(height: Space.lg.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.ink2,
                        side: BorderSide(color: c.line2),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: Space.sm.w),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      style: FilledButton.styleFrom(backgroundColor: c.call.solid),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One housemate's card: avatar, name (ellipsized to one line so a long
/// seeded test name like "Housemate 1 [TESTDATA-...]" never wraps or
/// overflows), role, and their live status badge — plus the admin kebab
/// when [canManage] is true.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.status,
    required this.now,
    required this.isMe,
    required this.canManage,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
  });

  final HouseMember member;
  final MemberStatus? status;
  final DateTime now;
  final bool isMe;
  final bool canManage;
  final VoidCallback onPromote;
  final VoidCallback onDemote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effectiveStatus = status?.effectiveStatus(now) ?? HouseStatus.openToChat;
    final effectiveExpiresAt = effectiveStatus == HouseStatus.openToChat ? null : status?.expiresAt;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
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
              Avatar(name: member.user.displayName, photoUrl: member.user.avatarUrl, size: 34.r),
              SizedBox(width: Space.md.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      member.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<_MemberAction>(
                  icon: Icon(Icons.more_vert, color: c.ink2, size: 20.r),
                  onSelected: (action) => switch (action) {
                    _MemberAction.promote => onPromote(),
                    _MemberAction.demote => onDemote(),
                    _MemberAction.remove => onRemove(),
                  },
                  itemBuilder: (context) => [
                    if (member.role != 'admin')
                      const PopupMenuItem(
                        value: _MemberAction.promote,
                        child: Text('Make admin'),
                      )
                    else
                      const PopupMenuItem(
                        value: _MemberAction.demote,
                        child: Text('Remove admin'),
                      ),
                    PopupMenuItem(
                      value: _MemberAction.remove,
                      child: Text('Remove from house', style: TextStyle(color: c.call.solid)),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: Space.sm.h),
          Padding(
            padding: EdgeInsets.only(left: 34.r + Space.md.w),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedValueSwitcher(
                value: (effectiveStatus, effectiveExpiresAt),
                builder: (context) =>
                    StatusBadge(status: effectiveStatus, expiresAt: effectiveExpiresAt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMembersState extends StatelessWidget {
  const _EmptyMembersState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Text(
        'No housemates yet.',
        style: context.text.bodySmall?.copyWith(color: c.ink3),
      ),
    );
  }
}

/// Shown when the search field's query matches nobody — distinct from
/// [_EmptyMembersState] (an empty house, which can't actually happen since
/// the caller is always a member, but is handled the same defensively).
class _NoSearchMatchesState extends StatelessWidget {
  const _NoSearchMatchesState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Space.base.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 28.r, color: c.ink3),
            SizedBox(height: Space.sm.h),
            Text(
              'No housemates match "$query"',
              style: context.text.bodyMedium?.copyWith(color: c.ink3),
              textAlign: TextAlign.center,
            ),
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
