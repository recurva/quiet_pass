import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/avatar.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'recurring_badge.dart';

/// The house's chores: the caller's own next chore (as a "chore pass" hero
/// card, matching the sheet shown right after booking — see
/// chore_pass_sheet.dart) with a Mark done action, then every other
/// housemate's pending chores below it. Reached from GroupDetailPage's
/// "Chores" entry card; this used to be two inline sections on
/// SpacesPage ("Yours · Due next" and "Housemates") — moved here so
/// Spaces stays about booking spaces, not about chores.
class ChoresPage extends ConsumerStatefulWidget {
  const ChoresPage({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  ConsumerState<ChoresPage> createState() => _ChoresPageState();
}

class _ChoresPageState extends ConsumerState<ChoresPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Same "refetch on resume" safety net SpacesPage already uses for its
  // own lists — a background tab's reconnect timer can be throttled well
  // past the chore_done WebSocket event actually arriving.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(groupChoresProvider(widget.groupId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groupId = widget.groupId;

    ref.watch(groupChoresLiveRefreshProvider(groupId));
    ref.watch(groupMembersLiveRefreshProvider(groupId));

    final choresAsync = ref.watch(groupChoresProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final reservationsAsync = ref.watch(groupReservationsProvider(groupId));
    final me = ref.watch(currentBackendUserProvider).valueOrNull;

    final namesById = <String, String>{
      for (final member in membersAsync.valueOrNull ?? const [])
        member.user.id: member.user.displayName,
    };
    final avatarUrlById = <String, String?>{
      for (final member in membersAsync.valueOrNull ?? const [])
        member.user.id: member.user.avatarUrl,
    };
    // Looked up per-chore to tell a one-off booking's chore apart from a
    // recurring series's, purely to show the "Weekly" badge — no new data
    // fetched, this just cross-references the reservations already loaded
    // above.
    final reservationById = <String, AppReservation>{
      for (final reservation in reservationsAsync.valueOrNull ?? const [])
        reservation.id: reservation,
    };

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
              choresAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(friendlyErrorMessage(error), style: context.text.bodySmall?.copyWith(color: c.ink3)),
                ),
                data: (chores) => _ChoresContent(
                  groupId: groupId,
                  chores: chores,
                  myUserId: me?.id,
                  reservationById: reservationById,
                  namesById: namesById,
                  avatarUrlById: avatarUrlById,
                ),
              ),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chores', style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Text(widget.groupName, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything below the header, split out as its own widget purely so
/// [ChoresPage] can hand the already-resolved chore list (and lookup
/// maps) down without re-deriving `mine`/`others` inline in a big build
/// method.
class _ChoresContent extends StatelessWidget {
  const _ChoresContent({
    required this.groupId,
    required this.chores,
    required this.myUserId,
    required this.reservationById,
    required this.namesById,
    required this.avatarUrlById,
  });

  final String groupId;
  final List<AppChore> chores;
  final String? myUserId;
  final Map<String, AppReservation> reservationById;
  final Map<String, String> namesById;
  final Map<String, String?> avatarUrlById;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = myUserId == null
        ? const <AppChore>[]
        : chores.where((chore) => chore.userId == myUserId && !chore.done).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    // Chores aren't anonymous — GET /groups/{id}/chores already returns
    // every member's chores, whoever it's assigned to (see the backend's
    // list_group_chores docstring) — so a housemate can see who still
    // owes what. "Done" stays out of this list entirely (read-only, no
    // action) — markChoreDone is assignee-only server-side regardless.
    final others = myUserId == null
        ? const <AppChore>[]
        : chores.where((chore) => chore.userId != myUserId && !chore.done).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR CHORE PASS',
          style: context.text.labelLarge?.copyWith(
            color: c.ink3,
            fontSize: 11.sp,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: Space.sm.h),
        if (mine.isEmpty)
          const _NothingDueCard()
        else
          Column(
            children: [
              FadeSlideIn(
                key: ValueKey('chore-${mine.first.id}'),
                child: _YourNextChoreCard(groupId: groupId, chore: mine.first),
              ),
              for (final row in _groupedChoreRows(
                chores: mine.skip(1).toList(),
                reservationById: reservationById,
                topPadding: Space.sm.h,
                buildRow: (chore, isWeekly) =>
                    _ChoreRow(groupId: groupId, chore: chore, isWeekly: isWeekly),
              ))
                row,
            ],
          ),
        SizedBox(height: Space.lg.h),
        Row(
          children: [
            Text(
              'HOUSE CHORE ROTATION',
              style: context.text.labelLarge?.copyWith(
                color: c.ink3,
                fontSize: 11.sp,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (others.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: Space.sm.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.pill.r),
                ),
                child: Text(
                  '${others.length} left',
                  style: context.text.bodySmall?.copyWith(
                    color: c.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: Space.sm.h),
        if (others.isEmpty)
          Text(
            'Nothing pending for anyone else.',
            style: context.text.bodySmall?.copyWith(color: c.ink3),
          )
        else
          for (final row in _groupedChoreRows(
            chores: others,
            reservationById: reservationById,
            topPadding: 0,
            bottomPadding: Space.sm.h,
            buildRow: (chore, isWeekly) => _OtherChoreRow(
              chore: chore,
              assigneeName: namesById[chore.userId] ?? 'A housemate',
              assigneeAvatarUrl: avatarUrlById[chore.userId],
              isWeekly: isWeekly,
            ),
            assigneeNameOf: (chore) => namesById[chore.userId] ?? 'A housemate',
            assigneeAvatarUrlOf: (chore) => avatarUrlById[chore.userId],
          ))
            row,
      ],
    );
  }
}

/// Friendly empty state for "nothing due" — shown in place of the chore
/// pass hero card when the caller has no pending chore of their own.
class _NothingDueCard extends StatelessWidget {
  const _NothingDueCard();

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
      child: Row(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.open.tint, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 20.r, color: c.open.solid),
          ),
          SizedBox(width: Space.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're all caught up",
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Nothing due on your end right now.',
                  style: context.text.bodySmall?.copyWith(color: c.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds one row per chore, except every chore whose reservation belongs
/// to the same recurring booking series collapses into a single
/// [_ChoreSeriesGroupRow] instead of one row each — the same bug class as
/// SpacesPage's reservation list, just for a recurring booking's chores
/// (tied to a reservation via [AppChore.reservationId], cross-referenced
/// against [reservationById] for [AppReservation.recurringSeriesId]). A
/// chore from a one-off booking still renders exactly as before via
/// [buildRow]. [chores] need not be pre-sorted; occurrences within a
/// group are sorted here by [AppChore.dueAt] ascending.
List<Widget> _groupedChoreRows({
  required List<AppChore> chores,
  required Map<String, AppReservation> reservationById,
  required Widget Function(AppChore chore, bool isWeekly) buildRow,
  double topPadding = 0,
  double bottomPadding = 0,
  String? Function(AppChore chore)? assigneeNameOf,
  String? Function(AppChore chore)? assigneeAvatarUrlOf,
}) {
  final rows = <Widget>[];
  final renderedSeriesIds = <String>{};
  for (final chore in chores) {
    final seriesId = reservationById[chore.reservationId]?.recurringSeriesId;
    if (seriesId == null) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: FadeSlideIn(
            key: ValueKey('chore-row-${chore.id}'),
            child: buildRow(chore, false),
          ),
        ),
      );
      continue;
    }
    if (renderedSeriesIds.contains(seriesId)) continue;
    renderedSeriesIds.add(seriesId);
    final groupChores = chores.where((c) => reservationById[c.reservationId]?.recurringSeriesId == seriesId).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    rows.add(
      Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: FadeSlideIn(
          key: ValueKey('chore-series-$seriesId'),
          child: _ChoreSeriesGroupRow(
            chores: groupChores,
            assigneeName: assigneeNameOf?.call(groupChores.first),
            assigneeAvatarUrl: assigneeAvatarUrlOf?.call(groupChores.first),
            rowBuilder: (c) => buildRow(c, true),
          ),
        ),
      ),
    );
  }
  return rows;
}

/// Collapsed summary for every occurrence of a recurring chore (one per
/// occurrence of its booking series) — mirrors SpacesPage's
/// `_SeriesReservationGroupRow` for the same bug class. Expanding shows
/// each occurrence via [rowBuilder] (the caller's own [_ChoreRow] or a
/// housemate's [_OtherChoreRow], unchanged), so marking a single
/// occurrence done keeps calling [GroupsRepository.markChoreDone] exactly
/// as before.
class _ChoreSeriesGroupRow extends StatefulWidget {
  const _ChoreSeriesGroupRow({
    required this.chores,
    required this.rowBuilder,
    this.assigneeName,
    this.assigneeAvatarUrl,
  });

  /// Every occurrence in the group, sorted by [AppChore.dueAt] ascending.
  final List<AppChore> chores;
  final Widget Function(AppChore chore) rowBuilder;
  /// Null for the caller's own chores (no avatar needed); set for a
  /// housemate's group, so the collapsed row still shows who it's for.
  final String? assigneeName;
  final String? assigneeAvatarUrl;

  @override
  State<_ChoreSeriesGroupRow> createState() => _ChoreSeriesGroupRowState();
}

class _ChoreSeriesGroupRowState extends State<_ChoreSeriesGroupRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = widget.chores.first;
    final isDue = DateTime.now().toUtc().isAfter(next.dueAt);

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
            onTap: () {
              Haptics.selection();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
              child: Row(
                children: [
                  if (widget.assigneeName != null) ...[
                    Avatar(name: widget.assigneeName!, photoUrl: widget.assigneeAvatarUrl, size: 32.r),
                    SizedBox(width: Space.md.w),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(next.template, style: context.text.bodyLarge),
                        SizedBox(height: Space.xs.h),
                        Row(
                          children: [
                            const RecurringBadge(),
                            SizedBox(width: Space.sm.w),
                            Expanded(
                              child: Text(
                                '${widget.assigneeName != null ? '${widget.assigneeName} · ' : ''}'
                                '${isDue ? 'Due now' : 'Next ${next.dueAt.toLocalDateTimeLabel()}'}'
                                ' · ${widget.chores.length} upcoming',
                                style: context.text.bodySmall?.copyWith(color: isDue ? c.call.solid : c.ink3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: Space.sm.w),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18.r, color: c.ink3),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(Space.md.w, 0, Space.md.w, Space.md.h),
              child: Column(
                children: [
                  for (final chore in widget.chores)
                    Padding(
                      padding: EdgeInsets.only(top: Space.sm.h),
                      child: widget.rowBuilder(chore),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The single most-urgent chore of the caller's own, shown as the mockup's
/// gradient-tinted hero "chore pass" card instead of a plain row — the
/// same title text as chore_pass_sheet.dart's "Your chore pass" sheet,
/// now living here permanently instead of only right after booking. Any
/// further chores of the caller's own render as plain [_ChoreRow]s
/// underneath.
class _YourNextChoreCard extends ConsumerStatefulWidget {
  const _YourNextChoreCard({required this.groupId, required this.chore});

  final String groupId;
  final AppChore chore;

  @override
  ConsumerState<_YourNextChoreCard> createState() => _YourNextChoreCardState();
}

class _YourNextChoreCardState extends ConsumerState<_YourNextChoreCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chore = widget.chore;
    final now = DateTime.now().toUtc();
    final isDue = now.isAfter(chore.dueAt);
    final isSoon = !isDue && chore.dueAt.difference(now) <= const Duration(hours: 1);
    final dueColor = isDue ? c.call.solid : (isSoon ? c.focus.solid : c.ink3);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.accentTint, c.accentTint.withValues(alpha: 0)],
        ),
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.accentRing),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR CHORE PASS',
            style: context.text.labelLarge?.copyWith(
              color: c.accent,
              fontSize: 11.sp,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: Space.xs.h),
          Text(
            chore.template,
            style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: Space.xs.h),
          Text(
            isDue ? 'Due now' : 'Due ${chore.dueAt.toLocalDateTimeLabel()}',
            style: context.text.bodyMedium?.copyWith(color: dueColor, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: Space.md.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _markDone,
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                    )
                  : const Text('Mark done'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markDone() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).markChoreDone(widget.chore.id);
      Haptics.commit();
      ref.invalidate(groupChoresProvider(widget.groupId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ChoreRow extends ConsumerStatefulWidget {
  const _ChoreRow({required this.groupId, required this.chore, required this.isWeekly});

  final String groupId;
  final AppChore chore;
  final bool isWeekly;

  @override
  ConsumerState<_ChoreRow> createState() => _ChoreRowState();
}

class _ChoreRowState extends ConsumerState<_ChoreRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chore = widget.chore;
    final isWeekly = widget.isWeekly;
    final isDue = DateTime.now().toUtc().isAfter(chore.dueAt);

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chore.template, style: context.text.bodyLarge),
                SizedBox(height: Space.xs.h),
                Row(
                  children: [
                    if (isWeekly) ...[
                      const RecurringBadge(),
                      SizedBox(width: Space.sm.w),
                    ],
                    Text(
                      isDue ? 'Due now' : 'Due ${chore.dueAt.toLocalDateTimeLabel()}',
                      style: context.text.bodySmall?.copyWith(
                        color: isDue ? c.call.solid : c.ink3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: Space.sm.w),
          OutlinedButton(
            onPressed: _busy ? null : _markDone,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink2,
              side: BorderSide(color: c.line2),
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
            ),
            child: _busy
                ? SizedBox(
                    width: 14.r,
                    height: 14.r,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                  )
                : const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _markDone() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).markChoreDone(widget.chore.id);
      Haptics.commit();
      ref.invalidate(groupChoresProvider(widget.groupId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Read-only counterpart to [_ChoreRow] for a housemate's own chore — no
/// "Done" button, since markChoreDone is assignee-only server-side
/// regardless of anything this screen shows or hides.
class _OtherChoreRow extends StatelessWidget {
  const _OtherChoreRow({
    required this.chore,
    required this.assigneeName,
    required this.assigneeAvatarUrl,
    required this.isWeekly,
  });

  final AppChore chore;
  final String assigneeName;
  final String? assigneeAvatarUrl;
  final bool isWeekly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDue = DateTime.now().toUtc().isAfter(chore.dueAt);

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
          Avatar(name: assigneeName, photoUrl: assigneeAvatarUrl, size: 32.r),
          SizedBox(width: Space.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chore.template, style: context.text.bodyLarge),
                SizedBox(height: Space.xs.h),
                Row(
                  children: [
                    if (isWeekly) ...[
                      const RecurringBadge(),
                      SizedBox(width: Space.sm.w),
                    ],
                    Expanded(
                      child: Text(
                        '$assigneeName · ${isDue ? 'Due now' : 'Due ${chore.dueAt.toLocalDateTimeLabel()}'}',
                        style: context.text.bodySmall?.copyWith(color: isDue ? c.call.solid : c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
