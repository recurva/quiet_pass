import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import 'custom_nudge_sheet.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'house_status_wire.dart';
import 'nudge_wire.dart';
import 'quiet_pulse_sheet.dart';
import 'spaces_page.dart';

enum _MemberAction { promote, demote, remove }

/// Reached by tapping a house on GroupsHomePage. Shows housemates with
/// their live status (pushed over the group's WebSocket) and lets the
/// caller set their own status.
class GroupDetailPage extends ConsumerStatefulWidget {
  const GroupDetailPage({super.key, required this.group});

  final AppGroup group;

  @override
  ConsumerState<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends ConsumerState<GroupDetailPage> {
  HouseStatus? _pendingStatus;
  int? _pendingDurationMinutes;
  NudgeType? _sendingPreset;
  bool _sendingQuietPulse = false;
  bool _handledOwnRemoval = false;

  // Nothing server-side pushes an update at the exact moment a status's
  // TTL lapses (Redis just lets the key expire silently) — this timer is
  // what makes an already-open screen notice the crossover and flip a
  // member's badge to Open to Chat without needing a fresh fetch.
  Timer? _expiryTick;

  @override
  void initState() {
    super.initState();
    _expiryTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now().toUtc();
    ref.watch(groupMembersLiveRefreshProvider(widget.group.id));
    final membersAsync = ref.watch(groupMembersProvider(widget.group.id));
    final statusesAsync = ref.watch(groupStatusesProvider(widget.group.id));
    final me = ref.watch(currentBackendUserProvider).valueOrNull;
    final statuses = statusesAsync.valueOrNull ?? const <String, MemberStatus>{};
    final myEntry = me == null ? null : statuses[me.id];
    final myEffectiveStatus = myEntry?.effectiveStatus(now) ?? HouseStatus.openToChat;
    final pendingNudges = ref.watch(groupPendingNudgesProvider(widget.group.id));
    final members = membersAsync.valueOrNull;
    final myMembership =
        me == null || members == null ? null : members.where((m) => m.user.id == me.id).firstOrNull;

    // Catches being kicked while this screen is open: the member list
    // just refetched (via groupMembersLiveRefreshProvider, above) and no
    // longer includes the caller. Guarded so this only fires once — a
    // voluntary leave already pops this screen itself before the
    // refetch even lands, but if that race ever goes the other way,
    // this would otherwise re-fire on every subsequent rebuild once
    // myMembership is permanently null.
    if (!_handledOwnRemoval && me != null && members != null && myMembership == null) {
      _handledOwnRemoval = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(myGroupsProvider);
        Navigator.of(context).popUntil((route) => route.isFirst);
        showAppSnackBar(context, "You've been removed from this house.");
      });
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (pendingNudges.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(Space.base.w, Space.base.h, Space.base.w, 0),
                child: Column(
                  children: [
                    for (final nudge in pendingNudges)
                      Padding(
                        padding: EdgeInsets.only(bottom: Space.sm.h),
                        child: _NudgeBanner(
                          nudge: nudge,
                          onDismiss: () => ref
                              .read(groupPendingNudgesProvider(widget.group.id).notifier)
                              .dismiss(nudge.id),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(Space.base.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, myMembership),
                    SizedBox(height: Space.lg.h),
                    _yourStatusCard(context, myEffectiveStatus),
                    SizedBox(height: Space.base.h),
                    _nudgesCard(context),
                    SizedBox(height: Space.base.h),
                    Text(
                      'HOUSEMATES',
                      style: context.text.labelLarge?.copyWith(
                        color: c.ink3,
                        fontSize: 11.sp,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: Space.sm.h),
                    membersAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => Padding(
                        padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                        child: Text(
                          friendlyErrorMessage(error),
                          style: context.text.bodySmall?.copyWith(color: c.ink3),
                        ),
                      ),
                      data: (members) {
                        final iAmAdmin = myMembership?.role == 'admin';
                        return Column(
                          children: [
                            for (final member in members)
                              Padding(
                                padding: EdgeInsets.only(bottom: Space.sm.h),
                                child: _memberRow(
                                  context,
                                  member,
                                  statuses[member.user.id],
                                  now,
                                  isMe: me != null && member.user.id == me.id,
                                  canManage: iAmAdmin && myMembership != null,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, HouseMember? myMembership) {
    final c = context.colors;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm.r),
            ),
          ),
          icon: Icon(Icons.arrow_back, color: c.ink2, size: 20.r),
        ),
        SizedBox(width: Space.md.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.group.name, style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Invite code: ${widget.group.inviteCode}',
                      style: context.text.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: Space.sm.w),
                  GestureDetector(
                    onTap: () => _copyInviteCode(context),
                    child: Icon(Icons.copy_rounded, size: 15.r, color: c.ink3),
                  ),
                  SizedBox(width: Space.md.w),
                  GestureDetector(
                    onTap: () => _shareInviteCode(context),
                    child: Icon(Icons.ios_share_rounded, size: 15.r, color: c.ink3),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: Space.sm.w),
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SpacesPage(groupId: widget.group.id, groupName: widget.group.name),
            ),
          ),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm.r),
            ),
          ),
          icon: Icon(Icons.meeting_room_outlined, color: c.ink2, size: 20.r),
        ),
        if (myMembership != null) ...[
          SizedBox(width: Space.sm.w),
          IconButton(
            onPressed: () => _leaveGroup(myMembership.membershipId),
            style: IconButton.styleFrom(
              backgroundColor: c.surface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.sm.r),
              ),
            ),
            icon: Icon(Icons.logout, color: c.call.solid, size: 20.r),
          ),
        ],
      ],
    );
  }

  Future<void> _copyInviteCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
    if (context.mounted) showAppSnackBar(context, 'Invite code copied.');
  }

  Future<void> _shareInviteCode(BuildContext context) async {
    await Share.share('Join my house on QuietPass. Code: ${widget.group.inviteCode}');
  }

  Widget _yourStatusCard(BuildContext context, HouseStatus myEffectiveStatus) {
    final c = context.colors;
    final displayedStatus = _pendingStatus ?? myEffectiveStatus;
    final rule = statusDurationRules[displayedStatus];

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
              for (final status in HouseStatus.values)
                StatusChip(
                  status: status,
                  selected: displayedStatus == status,
                  onTap: () => _selectStatus(status),
                ),
            ],
          ),
          // Open to Chat has no duration concept at all — no row shown.
          if (rule != null) ...[
            SizedBox(height: Space.sm.h),
            DurationSlider(
              allowedMinutes: rule.allowedMinutes,
              selectedMinutes: _pendingDurationMinutes ?? rule.defaultMinutes,
              formatLabel: formatDurationMinutes,
              onChangeEnd: (minutes) => _setStatus(displayedStatus, minutes),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nudgesCard(BuildContext context) {
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
          Text(
            'NUDGE THE HOUSE',
            style: context.text.labelLarge?.copyWith(
              color: c.ink3,
              fontSize: 11.sp,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: Space.xs.h),
          Text('Sent to everyone. No name attached.', style: context.text.bodySmall),
          SizedBox(height: Space.md.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sendingQuietPulse ? null : _sendQuietPulse,
              child: _sendingQuietPulse
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                    )
                  : const Text('Quiet pulse'),
            ),
          ),
          SizedBox(height: Space.sm.h),
          Wrap(
            spacing: Space.sm.w,
            runSpacing: Space.sm.h,
            children: [
              for (final preset in presetNudgeTypes)
                _PresetButton(
                  type: preset,
                  sending: _sendingPreset == preset,
                  onTap: () => _sendPreset(preset),
                ),
              _PresetButton(
                type: NudgeType.custom,
                sending: _sendingPreset == NudgeType.custom,
                onTap: _sendCustomNudge,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendQuietPulse() async {
    final minutes = await showQuietPulseSheet(context);
    if (minutes == null || !mounted) return; // dismissed without confirming

    setState(() => _sendingQuietPulse = true);
    try {
      await ref
          .read(groupsRepositoryProvider)
          .sendNudge(widget.group.id, NudgeType.quietPulse, durationMinutes: minutes);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _sendingQuietPulse = false);
    }
  }

  Future<void> _sendPreset(NudgeType type) async {
    setState(() => _sendingPreset = type);
    try {
      await ref.read(groupsRepositoryProvider).sendNudge(widget.group.id, type);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _sendingPreset = null);
    }
  }

  Future<void> _sendCustomNudge() async {
    final message = await showCustomNudgeSheet(context);
    if (message == null || !mounted) return; // dismissed without confirming

    setState(() => _sendingPreset = NudgeType.custom);
    try {
      await ref
          .read(groupsRepositoryProvider)
          .sendNudge(widget.group.id, NudgeType.custom, message: message);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _sendingPreset = null);
    }
  }

  Widget _memberRow(
    BuildContext context,
    HouseMember member,
    MemberStatus? status,
    DateTime now, {
    required bool isMe,
    required bool canManage,
  }) {
    final c = context.colors;
    final effectiveStatus = status?.effectiveStatus(now) ?? HouseStatus.openToChat;
    final effectiveExpiresAt = effectiveStatus == HouseStatus.openToChat ? null : status?.expiresAt;
    // An admin can manage anyone but themself here — self-removal is
    // "Leave house" (see _header), a deliberately separate, more visible
    // action rather than being buried in this per-row menu.
    final showMenu = canManage && !isMe;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      // A Column, not a single Row with the badge as a trailing element —
      // "Sleeping Early · until 10:34 PM" is long enough that squeezing it
      // into the same row as the name/role pushed those into wrapping
      // ("Collector" → "Collec-/tor") on narrower phones. The badge gets
      // its own row below instead, so name/role always have the full
      // width to themselves.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34.r,
                height: 34.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                child: Text(
                  member.user.displayName.characters.take(2).toString().toUpperCase(),
                  style: context.text.labelLarge?.copyWith(
                    color: c.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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
              if (showMenu)
                PopupMenuButton<_MemberAction>(
                  icon: Icon(Icons.more_vert, color: c.ink2, size: 20.r),
                  onSelected: (action) => switch (action) {
                    _MemberAction.promote => _promoteMember(member),
                    _MemberAction.demote => _demoteMember(member),
                    _MemberAction.remove => _removeMember(member),
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
              child: StatusBadge(status: effectiveStatus, expiresAt: effectiveExpiresAt),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promoteMember(HouseMember member) async {
    try {
      await ref.read(groupsRepositoryProvider).promoteToAdmin(member.membershipId);
      ref.invalidate(groupMembersProvider(widget.group.id));
      if (mounted) showAppSnackBar(context, '${member.user.displayName} is now an admin.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _demoteMember(HouseMember member) async {
    try {
      await ref.read(groupsRepositoryProvider).demoteToMember(member.membershipId);
      ref.invalidate(groupMembersProvider(widget.group.id));
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
      ref.invalidate(groupMembersProvider(widget.group.id));
      if (mounted) showAppSnackBar(context, '${member.user.displayName} was removed.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _leaveGroup(String myMembershipId) async {
    final confirmed = await _showConfirmSheet(
      context,
      title: 'Leave ${widget.group.name}?',
      body: "You'll need a new invite to rejoin.",
      confirmLabel: 'Leave',
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(groupsRepositoryProvider).removeMembership(myMembershipId);
      ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.of(context).pop();
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
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
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

  /// Tapping a status chip: Open to Chat applies immediately (no duration
  /// concept). Any other status applies immediately too, at its default
  /// duration — the picker row then lets the caller change to a different
  /// allowed preset, which re-applies via [_setStatus] again. This keeps
  /// the existing snappy "tap chip → set" feel while still satisfying the
  /// spec's "pre-select the default but allow any allowed option."
  Future<void> _selectStatus(HouseStatus status) async {
    if (status == HouseStatus.openToChat) {
      await _setStatus(status, null);
      return;
    }
    await _setStatus(status, statusDurationRules[status]!.defaultMinutes);
  }

  Future<void> _setStatus(HouseStatus status, int? durationMinutes) async {
    setState(() {
      _pendingStatus = status;
      _pendingDurationMinutes = durationMinutes;
    });
    try {
      await ref
          .read(groupsRepositoryProvider)
          .setMyStatus(widget.group.id, status, durationMinutes: durationMinutes);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _pendingStatus = null);
    }
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.type, required this.sending, required this.onTap});

  final NudgeType type;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton(
      onPressed: sending ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink2,
        side: BorderSide(color: c.line2),
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
      ),
      child: sending
          ? SizedBox(
              width: 14.r,
              height: 14.r,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
            )
          : Text(type.presetLabel),
    );
  }
}

/// Calm, transient in-app banner for a received nudge. Never shows a
/// sender — [AppNudge] has no sender field to show even if this wanted to.
class _NudgeBanner extends StatelessWidget {
  const _NudgeBanner({required this.nudge, required this.onDismiss});

  final AppNudge nudge;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        decoration: BoxDecoration(
          color: c.accentTint,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: c.accentRing),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                nudge.message,
                style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: Space.sm.w),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, color: c.ink2, size: 18.r),
            ),
          ],
        ),
      ),
    );
  }
}
