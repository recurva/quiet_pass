import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/avatar.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import 'agreements_page.dart';
import 'custom_nudge_sheet.dart';
import 'dinner_wire.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'house_status_wire.dart';
import 'house_tools_sheet.dart';
import 'nudge_wire.dart';
import 'quiet_pulse_sheet.dart';
import 'spaces_page.dart';
import 'status_picker_sheet.dart';
import 'wifi_page.dart';

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
  DinnerStatus? _pendingDinnerStatus;

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
    ref.watch(groupDinnerLiveRefreshProvider(widget.group.id));
    final membersAsync = ref.watch(groupMembersProvider(widget.group.id));
    final dinnerAsync = ref.watch(groupDinnerSummaryProvider(widget.group.id));
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
                        child: FadeSlideIn(
                          key: ValueKey('nudge-${nudge.id}'),
                          child: _NudgeBanner(
                            nudge: nudge,
                            onDismiss: () => ref
                                .read(groupPendingNudgesProvider(widget.group.id).notifier)
                                .dismiss(nudge.id),
                          ),
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
                    SizedBox(height: Space.sm.h),
                    Padding(
                      padding: EdgeInsets.only(left: 44.r),
                      child: _inviteCodePill(context),
                    ),
                    SizedBox(height: Space.base.h),
                    _spacesEntry(context),
                    SizedBox(height: Space.lg.h),
                    _yourStatusCard(context, myEffectiveStatus, myEntry?.expiresAt),
                    SizedBox(height: Space.base.h),
                    _dinnerCard(context, dinnerAsync, members, me?.id),
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
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.md.r),
                        border: Border.all(color: c.line),
                      ),
                      child: membersAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (error, _) => Padding(
                          padding: EdgeInsets.all(Space.base.w),
                          child: Text(
                            friendlyErrorMessage(error),
                            style: context.text.bodySmall?.copyWith(color: c.ink3),
                          ),
                        ),
                        data: (members) {
                          final iAmAdmin = myMembership?.role == 'admin';
                          return Column(
                            children: [
                              for (var i = 0; i < members.length; i++) ...[
                                if (i > 0) Divider(height: 1, color: c.line),
                                _memberRow(
                                  context,
                                  members[i],
                                  statuses[members[i].user.id],
                                  now,
                                  isMe: me != null && members[i].user.id == me.id,
                                  canManage: iAmAdmin && myMembership != null,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
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

  /// Identity only: back, name, leave. Occasional-tool entry points used
  /// to accumulate here as one pill per feature — that queue is gone now;
  /// see [_toolsButton] and [_spacesEntry] for where those actions live
  /// instead.
  Widget _header(BuildContext context, HouseMember? myMembership) {
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
          child: Text(
            widget.group.name,
            style: context.text.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: Space.sm.w),
        _toolsButton(context, myMembership),
        if (myMembership != null) ...[
          SizedBox(width: Space.sm.w),
          IconButton(
            onPressed: () => _leaveGroup(myMembership.membershipId),
            style: IconButton.styleFrom(
              backgroundColor: c.surface2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
            ),
            icon: Icon(Icons.logout, color: c.call.solid, size: 20.r),
          ),
        ],
      ],
    );
  }

  /// Opens the house-tools sheet (Agreements, Guest Wi-Fi today) — the one
  /// icon that replaced two persistent pills on the main screen. Future
  /// occasional features get a row in that sheet, not a new icon here.
  Widget _toolsButton(BuildContext context, HouseMember? myMembership) {
    final c = context.colors;
    return IconButton(
      onPressed: () => _openHouseTools(context, myMembership),
      style: IconButton.styleFrom(
        backgroundColor: c.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
      ),
      icon: Icon(Icons.apps_rounded, color: c.ink2, size: 20.r),
    );
  }

  Future<void> _openHouseTools(BuildContext context, HouseMember? myMembership) async {
    final isAdmin = myMembership?.role == 'admin';
    final tool = await showHouseToolsSheet(context);
    if (tool == null || !context.mounted) return;

    switch (tool) {
      case HouseTool.agreements:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgreementsPage(
              groupId: widget.group.id,
              groupName: widget.group.name,
              isAdmin: isAdmin,
            ),
          ),
        );
      case HouseTool.wifi:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WifiPage(
              groupId: widget.group.id,
              groupName: widget.group.name,
              isAdmin: isAdmin,
            ),
          ),
        );
    }
  }

  /// Booking a space happens a few times a week in a shared house — more
  /// often than the occasional tools tucked behind [_toolsButton] — so it
  /// stays directly on screen as its own clear entry, not buried in a
  /// sheet.
  Widget _spacesEntry(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SpacesPage(groupId: widget.group.id, groupName: widget.group.name),
        ),
      ),
      borderRadius: BorderRadius.circular(Radii.md.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(Icons.meeting_room_outlined, size: 20.r, color: c.ink2),
            SizedBox(width: Space.md.w),
            Expanded(
              child: Text(
                'Spaces',
                style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, size: 20.r, color: c.ink3),
          ],
        ),
      ),
    );
  }

  Widget _inviteCodePill(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressFeedback(
          onTap: () => _copyInviteCode(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(Radii.pill.r),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.group.inviteCode,
                  style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(width: Space.xs.w),
                Icon(Icons.copy_rounded, size: 14.r, color: c.ink3),
              ],
            ),
          ),
        ),
        SizedBox(width: Space.sm.w),
        PressFeedback(
          onTap: () => _shareInviteCode(context),
          child: Container(
            padding: EdgeInsets.all(Space.xs.w),
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: c.line2),
            ),
            child: Icon(Icons.ios_share_rounded, size: 14.r, color: c.ink3),
          ),
        ),
      ],
    );
  }

  Future<void> _copyInviteCode(BuildContext context) async {
    Haptics.selection();
    await Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
    if (context.mounted) showAppSnackBar(context, 'Invite code copied.');
  }

  Future<void> _shareInviteCode(BuildContext context) async {
    await Share.share('Join my house on QuietPass. Code: ${widget.group.inviteCode}');
  }

  Widget _yourStatusCard(BuildContext context, HouseStatus myEffectiveStatus, DateTime? myExpiresAt) {
    final c = context.colors;
    final displayedStatus = _pendingStatus ?? myEffectiveStatus;
    final style = c.statusOf(displayedStatus);

    String caption;
    if (displayedStatus == HouseStatus.openToChat) {
      caption = 'Free to talk · no timer';
    } else {
      final expiresAt = _pendingStatus != null && _pendingDurationMinutes != null
          ? DateTime.now().add(Duration(minutes: _pendingDurationMinutes!))
          : myExpiresAt;
      caption = expiresAt == null ? displayedStatus.label : 'Until ${expiresAt.toLocalTimeLabel()}';
    }

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
              Text(
                'YOUR STATUS',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              PressFeedback(
                onTap: () => _openStatusPicker(context, displayedStatus),
                child: Text(
                  'Change',
                  style: context.text.bodyMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          SizedBox(height: Space.md.h),
          AnimatedValueSwitcher(
            value: displayedStatus,
            builder: (context) => Container(
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(Radii.pill.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8.r,
                    height: 8.r,
                    decoration: BoxDecoration(color: c.onAccent, shape: BoxShape.circle),
                  ),
                  SizedBox(width: Space.sm.w),
                  Text(
                    displayedStatus.label,
                    style: context.text.labelLarge?.copyWith(color: c.onAccent, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: Space.xs.h),
          Text(caption, style: context.text.bodySmall?.copyWith(color: style.ink)),
        ],
      ),
    );
  }

  Future<void> _openStatusPicker(BuildContext context, HouseStatus displayedStatus) async {
    final result = await showStatusPickerSheet(
      context,
      current: displayedStatus,
      currentDurationMinutes: _pendingDurationMinutes ?? statusDurationRules[displayedStatus]?.defaultMinutes,
    );
    if (result == null || !mounted) return; // dismissed without confirming
    await _setStatus(result.$1, result.$2);
  }

  /// Who's home for dinner tonight, per house. A daily, per-member toggle —
  /// [DinnerSummary] always reflects today (house-local, fixed IST; see
  /// dinner_service.py), so there's no explicit "reset" to trigger, the
  /// same "absence is the default" shape [HouseStatus] already uses.
  /// [cutoffPassed] is purely informational (shown as "Final"); tapping a
  /// toggle after 5pm still goes through — the backend never rejects it.
  Widget _dinnerCard(
    BuildContext context,
    AsyncValue<DinnerSummary> dinnerAsync,
    List<HouseMember>? members,
    String? myUserId,
  ) {
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
              Text(
                'DINNER TONIGHT',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (dinnerAsync.valueOrNull?.cutoffPassed == true)
                Text(
                  'FINAL AT 5 PM',
                  style: context.text.labelLarge?.copyWith(
                    color: c.ink3,
                    fontSize: 10.sp,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
          SizedBox(height: Space.md.h),
          dinnerAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(
              friendlyErrorMessage(error),
              style: context.text.bodySmall?.copyWith(color: c.ink3),
            ),
            data: (summary) {
              final myResponse =
                  myUserId == null ? null : summary.responses.where((r) => r.userId == myUserId).firstOrNull;
              final displayedStatus = _pendingDinnerStatus ?? myResponse?.status;
              final homeNames = [
                for (final response in summary.responses)
                  if (response.status == DinnerStatus.home)
                    _displayNameFor(response.userId, members, myUserId),
              ];
              final homeMembers = [
                for (final response in summary.responses)
                  if (response.status == DinnerStatus.home)
                    members?.where((m) => m.user.id == response.userId).firstOrNull,
              ].whereType<HouseMember>().toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedValueSwitcher(
                          value: (summary.homeCount, summary.stayingOutCount),
                          builder: (context) => Text(
                            '${summary.homeCount} home · ${summary.stayingOutCount} out',
                            style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (homeMembers.isNotEmpty) _AvatarStack(members: homeMembers),
                    ],
                  ),
                  if (homeNames.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      homeNames.join(', '),
                      style: context.text.bodySmall?.copyWith(color: c.ink3),
                    ),
                  ],
                  SizedBox(height: Space.md.h),
                  Row(
                    children: [
                      Expanded(
                        child: _DinnerChip(
                          label: 'Home for dinner',
                          selected: displayedStatus == DinnerStatus.home,
                          onTap: () => _setDinnerStatus(DinnerStatus.home),
                        ),
                      ),
                      SizedBox(width: Space.sm.w),
                      Expanded(
                        child: _DinnerChip(
                          label: 'Staying out',
                          selected: displayedStatus == DinnerStatus.stayingOut,
                          onTap: () => _setDinnerStatus(DinnerStatus.stayingOut),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _displayNameFor(String userId, List<HouseMember>? members, String? myUserId) {
    if (userId == myUserId) return 'You';
    return members?.where((m) => m.user.id == userId).firstOrNull?.user.displayName ?? 'A housemate';
  }

  Future<void> _setDinnerStatus(DinnerStatus status) async {
    setState(() => _pendingDinnerStatus = status);
    Haptics.selection();
    try {
      await ref.read(groupsRepositoryProvider).setDinnerStatus(widget.group.id, status);
      Haptics.commit();
      // Awaited, not fire-and-forget: clearing _pendingDinnerStatus before
      // the refetch actually lands meant the card briefly fell back to the
      // *old* cached summary (still showing the previous status) for one
      // frame before the new data arrived — a visible flicker/"swap" on
      // every tap. Waiting here means the real data already matches the
      // optimistic choice by the time the optimistic state is cleared.
      final _ = await ref.refresh(groupDinnerSummaryProvider(widget.group.id).future);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _pendingDinnerStatus = null);
    }
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
          SizedBox(height: Space.lg.h),
          Text(
            'QUICK ALERTS',
            style: context.text.labelLarge?.copyWith(
              color: c.ink3,
              fontSize: 11.sp,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: Space.sm.h),
          _quickAlertsGrid(context),
        ],
      ),
    );
  }

  /// The 2-up "QUICK ALERTS" grid: the 3 one-tap presets plus a "Custom"
  /// tile. Laid out as two explicit rows rather than a Wrap/GridView so
  /// each tile stays intrinsically sized (no fixed height on a
  /// text-containing box) while still lining up into equal columns.
  Widget _quickAlertsGrid(BuildContext context) {
    final tiles = [
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
    ];
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? Space.sm.h : 0),
            child: Row(
              children: [
                Expanded(child: tiles[i]),
                if (i + 1 < tiles.length) ...[
                  SizedBox(width: Space.sm.w),
                  Expanded(child: tiles[i + 1]),
                ],
              ],
            ),
          ),
      ],
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
      Haptics.commit();
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
      Haptics.commit();
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
      Haptics.commit();
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
    return FadeSlideIn(
      key: ValueKey('member-${member.membershipId}'),
      child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
      // No border/card of its own any more — the parent HOUSEMATES
      // container (see build()) supplies the single surrounding card, with
      // a hairline Divider between rows instead of each row being its own
      // bordered card.
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
              child: AnimatedValueSwitcher(
                value: (effectiveStatus, effectiveExpiresAt),
                builder: (context) =>
                    StatusBadge(status: effectiveStatus, expiresAt: effectiveExpiresAt),
              ),
            ),
          ),
        ],
      ),
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

  Future<void> _setStatus(HouseStatus status, int? durationMinutes) async {
    setState(() {
      _pendingStatus = status;
      _pendingDurationMinutes = durationMinutes;
    });
    Haptics.selection();
    try {
      await ref
          .read(groupsRepositoryProvider)
          .setMyStatus(widget.group.id, status, durationMinutes: durationMinutes);
      Haptics.commit();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _pendingStatus = null);
    }
  }
}

/// A small row of overlapping avatars for whoever's home for dinner — the
/// mockup's "overlapping avatar stack" next to the home/out count. Purely
/// decorative on top of [Avatar]; no new avatar-rendering logic.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});

  final List<HouseMember> members;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const avatarSize = 24.0;
    final shown = members.take(4).toList();
    final overlap = avatarSize.r * 0.6;
    return SizedBox(
      width: avatarSize.r + (shown.length - 1) * overlap,
      height: avatarSize.r,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.surface, width: 2.r)),
                child: Avatar(
                  name: shown[i].user.displayName,
                  photoUrl: shown[i].user.avatarUrl,
                  size: avatarSize.r,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DinnerChip extends StatelessWidget {
  const _DinnerChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accentRing : c.line2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: selected ? c.accent : c.ink2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// One tile in the "QUICK ALERTS" 2-up grid — an icon over a label, tapping
/// sends that preset immediately (or, for [NudgeType.custom], opens the
/// text-entry sheet). Visual-only redesign of what used to be a row of
/// outlined buttons; the tap handler and loading state are unchanged.
class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.type, required this.sending, required this.onTap});

  final NudgeType type;
  final bool sending;
  final VoidCallback onTap;

  IconData get _icon => switch (type) {
        NudgeType.packageArrived => Icons.inventory_2_outlined,
        NudgeType.frontDoorUnlocked => Icons.lock_open_outlined,
        NudgeType.sinkFull => Icons.water_drop_outlined,
        NudgeType.custom => Icons.add_rounded,
        NudgeType.quietPulse => Icons.nightlight_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      onTap: sending ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sending
                ? SizedBox(
                    width: 20.r,
                    height: 20.r,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                  )
                : Icon(_icon, size: 20.r, color: c.ink2),
            SizedBox(height: Space.sm.h),
            Text(
              type.presetLabel,
              style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
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
            PressFeedback(
              onTap: onDismiss,
              child: Icon(Icons.close, color: c.ink2, size: 18.r),
            ),
          ],
        ),
      ),
    );
  }
}
