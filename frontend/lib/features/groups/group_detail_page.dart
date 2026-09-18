import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/status_widgets.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'house_status_wire.dart';
import 'nudge_wire.dart';
import 'quiet_pulse_sheet.dart';
import 'spaces_page.dart';

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
  StatusTtlOption _selectedTtl = StatusTtlOption.fourHours;
  HouseStatus? _pendingStatus;
  NudgeType? _sendingPreset;
  bool _sendingQuietPulse = false;

  AppNudge? _bannerNudge;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final membersAsync = ref.watch(groupMembersProvider(widget.group.id));
    final statusesAsync = ref.watch(groupStatusesProvider(widget.group.id));
    final me = ref.watch(currentBackendUserProvider).valueOrNull;
    final statuses = statusesAsync.valueOrNull ?? const <String, MemberStatus>{};
    final myStatus = me == null ? null : statuses[me.id]?.status;

    ref.listen<AsyncValue<AppNudge>>(groupNudgesProvider(widget.group.id), (previous, next) {
      final nudge = next.valueOrNull;
      if (nudge == null) return;
      _bannerTimer?.cancel();
      setState(() => _bannerNudge = nudge);
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _bannerNudge = null);
      });
    });

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (_bannerNudge != null)
              Padding(
                padding: EdgeInsets.fromLTRB(Space.base.w, Space.base.h, Space.base.w, 0),
                child: _NudgeBanner(
                  nudge: _bannerNudge!,
                  onDismiss: () {
                    _bannerTimer?.cancel();
                    setState(() => _bannerNudge = null);
                  },
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(Space.base.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context),
                    SizedBox(height: Space.lg.h),
                    _yourStatusCard(context, myStatus),
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
                          '$error',
                          style: context.text.bodySmall?.copyWith(color: c.ink3),
                        ),
                      ),
                      data: (members) => Column(
                        children: [
                          for (final member in members)
                            Padding(
                              padding: EdgeInsets.only(bottom: Space.sm.h),
                              child: _memberRow(context, member, statuses[member.user.id]),
                            ),
                        ],
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

  Widget _header(BuildContext context) {
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
              Text('Invite code: ${widget.group.inviteCode}', style: context.text.bodySmall),
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
      ],
    );
  }

  Widget _yourStatusCard(BuildContext context, HouseStatus? myStatus) {
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
                  selected: (_pendingStatus ?? myStatus) == status,
                  onTap: () => _setStatus(status),
                ),
            ],
          ),
          SizedBox(height: Space.md.h),
          Row(
            children: [
              Text('Expires after', style: context.text.bodySmall),
              SizedBox(width: Space.sm.w),
              for (final option in StatusTtlOption.values) ...[
                _TtlOption(
                  option: option,
                  selected: _selectedTtl == option,
                  onTap: () => setState(() => _selectedTtl = option),
                ),
                SizedBox(width: Space.xs.w),
              ],
            ],
          ),
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

  Widget _memberRow(BuildContext context, HouseMember member, MemberStatus? status) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Row(
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
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 1.h),
                Text(member.role, style: context.text.bodySmall),
              ],
            ),
          ),
          status?.status == null ? const NoStatusBadge() : StatusBadge(status: status!.status!),
        ],
      ),
    );
  }

  Future<void> _setStatus(HouseStatus status) async {
    setState(() => _pendingStatus = status);
    try {
      await ref
          .read(groupsRepositoryProvider)
          .setMyStatus(widget.group.id, status, _selectedTtl.seconds);
    } finally {
      if (mounted) setState(() => _pendingStatus = null);
    }
  }
}

class _TtlOption extends StatelessWidget {
  const _TtlOption({required this.option, required this.selected, required this.onTap});

  final StatusTtlOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: Space.sm.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(Radii.pill.r),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          option.label,
          style: context.text.bodySmall?.copyWith(
            color: selected ? c.onAccent : c.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
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
