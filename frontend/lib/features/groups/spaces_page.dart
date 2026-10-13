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
import 'booking_sheet.dart';
import 'chore_pass_sheet.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'recurring_series_result_sheet.dart';
import 'recurring_series_sheet.dart';

/// Bookable spaces for a group: each space's upcoming reservations, a way
/// to book one, and the caller's own chore passes from past bookings.
class SpacesPage extends ConsumerStatefulWidget {
  const SpacesPage({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  ConsumerState<SpacesPage> createState() => _SpacesPageState();
}

class _SpacesPageState extends ConsumerState<SpacesPage> with WidgetsBindingObserver {
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

  // The WebSocket `reservation` event is the primary live-update path, but
  // a background browser tab gets its JS timers throttled — including the
  // client's own reconnect timer — so a socket that drops while this tab
  // isn't focused can stay down well past a normal 3s reconnect, silently
  // missing events published in the meantime. Refetching on resume is a
  // cheap safety net that doesn't depend on the socket having stayed alive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(groupReservationsProvider(widget.groupId));
      ref.invalidate(groupChoresProvider(widget.groupId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groupId = widget.groupId;

    // Keeps the reservation/chore lists refetched live as WebSocket
    // `reservation` events arrive — see the provider's doc comment.
    ref.watch(groupReservationsLiveRefreshProvider(groupId));
    ref.watch(groupMembersLiveRefreshProvider(groupId));
    ref.watch(groupChoresLiveRefreshProvider(groupId));
    ref.watch(groupMyRecurringSeriesLiveRefreshProvider(groupId));

    final spacesAsync = ref.watch(groupSpacesProvider(groupId));
    final reservationsAsync = ref.watch(groupReservationsProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final choresAsync = ref.watch(groupChoresProvider(groupId));
    final mySeriesAsync = ref.watch(groupMyRecurringSeriesProvider(groupId));
    final pendingUrgentRequests = ref.watch(groupPendingUrgentAccessRequestsProvider(groupId));
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
    final isAdmin = me == null
        ? false
        : (membersAsync.valueOrNull ?? const [])
                .where((m) => m.user.id == me.id)
                .firstOrNull
                ?.role ==
            'admin';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              if (pendingUrgentRequests.isNotEmpty) ...[
                SizedBox(height: Space.lg.h),
                for (final request in pendingUrgentRequests)
                  Padding(
                    padding: EdgeInsets.only(bottom: Space.sm.h),
                    child: FadeSlideIn(
                      key: ValueKey('urgent-${request.reservationId}-${request.requesterId}'),
                      child: _UrgentAccessBanner(
                        request: request,
                        requesterName: namesById[request.requesterId] ?? 'A housemate',
                        spaceName: (spacesAsync.valueOrNull ?? const [])
                                .where((s) => s.id == request.spaceId)
                                .firstOrNull
                                ?.name ??
                            'a space',
                        onDismiss: () => ref
                            .read(groupPendingUrgentAccessRequestsProvider(groupId).notifier)
                            .dismiss(request.reservationId, request.requesterId),
                      ),
                    ),
                  ),
              ],
              SizedBox(height: Space.lg.h),
              Text(
                'SPACES',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              spacesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(friendlyErrorMessage(error), style: context.text.bodySmall?.copyWith(color: c.ink3)),
                ),
                data: (spaces) => Column(
                  children: [
                    for (final space in spaces)
                      Padding(
                        padding: EdgeInsets.only(bottom: Space.sm.h),
                        child: _SpaceCard(
                          groupId: groupId,
                          space: space,
                          reservations: (reservationsAsync.valueOrNull ?? const [])
                              .where((r) => r.spaceId == space.id)
                              .toList(),
                          namesById: namesById,
                          avatarUrlById: avatarUrlById,
                          myUserId: me?.id,
                          isAdmin: isAdmin,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: Space.base.h),
              Text(
                'YOURS · DUE NEXT',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              choresAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(friendlyErrorMessage(error), style: context.text.bodySmall?.copyWith(color: c.ink3)),
                ),
                data: (chores) {
                  final mine = me == null
                      ? const <AppChore>[]
                      : chores.where((chore) => chore.userId == me.id && !chore.done).toList()
                    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
                  if (mine.isEmpty) {
                    return Text(
                      'Nothing pending.',
                      style: context.text.bodySmall?.copyWith(color: c.ink3),
                    );
                  }
                  final next = mine.first;
                  final rest = mine.skip(1).toList();
                  return Column(
                    children: [
                      FadeSlideIn(
                        key: ValueKey('chore-${next.id}'),
                        child: _YourNextChoreCard(groupId: groupId, chore: next),
                      ),
                      for (final chore in rest)
                        Padding(
                          padding: EdgeInsets.only(top: Space.sm.h),
                          child: FadeSlideIn(
                            key: ValueKey('chore-${chore.id}'),
                            child: _ChoreRow(
                              groupId: groupId,
                              chore: chore,
                              isWeekly: reservationById[chore.reservationId]?.recurringSeriesId != null,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              SizedBox(height: Space.base.h),
              choresAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                // Chores aren't anonymous — GET /groups/{id}/chores already
                // returns every member's chores, whoever it's assigned to
                // (see the backend's list_group_chores docstring); this was
                // previously fetched but then filtered down to just the
                // caller's own before ever reaching the screen, so a
                // housemate had no way to see who still owed what. "Done"
                // stays out of this list entirely (read-only, no action) —
                // markChoreDone is assignee-only server-side regardless.
                data: (chores) {
                  final others = me == null
                      ? const <AppChore>[]
                      : chores.where((chore) => chore.userId != me.id && !chore.done).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'HOUSEMATES',
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
                        for (final chore in others)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.sm.h),
                          child: FadeSlideIn(
                            key: ValueKey('other-chore-${chore.id}'),
                            child: _OtherChoreRow(
                              chore: chore,
                              assigneeName: namesById[chore.userId] ?? 'A housemate',
                              assigneeAvatarUrl: avatarUrlById[chore.userId],
                              isWeekly: reservationById[chore.reservationId]?.recurringSeriesId != null,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              SizedBox(height: Space.base.h),
              Text(
                'YOUR RECURRING BOOKINGS',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              mySeriesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(friendlyErrorMessage(error), style: context.text.bodySmall?.copyWith(color: c.ink3)),
                ),
                data: (series) {
                  if (series.isEmpty) {
                    return Text(
                      'No weekly bookings yet. Tap "Book weekly" on a space above.',
                      style: context.text.bodySmall?.copyWith(color: c.ink3),
                    );
                  }
                  final spaceNamesById = <String, String>{
                    for (final space in spacesAsync.valueOrNull ?? const []) space.id: space.name,
                  };
                  return Column(
                    children: [
                      for (final s in series)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.sm.h),
                          child: FadeSlideIn(
                            key: ValueKey('series-${s.id}'),
                            child: _RecurringSeriesRow(
                              groupId: groupId,
                              series: s,
                              spaceName: spaceNamesById[s.spaceId] ?? 'A space',
                            ),
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
              Text('Spaces', style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Text(widget.groupName, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpaceCard extends ConsumerWidget {
  const _SpaceCard({
    required this.groupId,
    required this.space,
    required this.reservations,
    required this.namesById,
    required this.avatarUrlById,
    required this.myUserId,
    required this.isAdmin,
  });

  final String groupId;
  final AppSpace space;
  final List<AppReservation> reservations;
  final Map<String, String> namesById;
  final Map<String, String?> avatarUrlById;
  final String? myUserId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sorted = [...reservations]..sort((a, b) => a.startTime.compareTo(b.startTime));
    final now = DateTime.now().toUtc();
    final activeNow = sorted
        .where((r) => !now.isBefore(r.startTime) && now.isBefore(r.endTime))
        .firstOrNull;
    final isFree = activeNow == null;

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
              Container(
                width: 36.r,
                height: 36.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.sm.r),
                ),
                child: Icon(Icons.meeting_room_outlined, size: 18.r, color: c.ink2),
              ),
              SizedBox(width: Space.md.w),
              Expanded(
                child: Text(
                  space.name,
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                isFree ? 'Free' : 'In use',
                style: context.text.bodyMedium?.copyWith(
                  color: isFree ? c.open.solid : c.call.solid,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (activeNow != null) ...[
            SizedBox(height: Space.sm.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
              decoration: BoxDecoration(
                color: c.call.tint,
                borderRadius: BorderRadius.circular(Radii.sm.r),
              ),
              child: Row(
                children: [
                  Avatar(
                    name: namesById[activeNow.userId] ?? 'A housemate',
                    photoUrl: avatarUrlById[activeNow.userId],
                    size: 22.r,
                  ),
                  SizedBox(width: Space.sm.w),
                  Expanded(
                    child: Text(
                      '${namesById[activeNow.userId] ?? 'A housemate'} · '
                      '${activeNow.startTime.toLocalTimeLabel()} – ${activeNow.endTime.toLocalTimeLabel()}',
                      style: context.text.bodySmall?.copyWith(color: c.call.ink, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (sorted.isEmpty) ...[
            SizedBox(height: Space.sm.h),
            Text('Nothing booked.', style: context.text.bodySmall?.copyWith(color: c.ink3)),
          ] else ...[
            SizedBox(height: Space.sm.h),
            for (final row in _reservationRows(sorted, now)) row,
          ],
          SizedBox(height: Space.sm.h),
          Row(
            children: [
              Expanded(
                child: isFree
                    ? FilledButton(
                        onPressed: () => _book(context, ref),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: Space.xs.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                        ),
                        child: const Text('Book'),
                      )
                    : OutlinedButton(
                        onPressed: () => _book(context, ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink2,
                          side: BorderSide(color: c.line2),
                          padding: EdgeInsets.symmetric(vertical: Space.xs.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                        ),
                        child: const Text('Book now'),
                      ),
              ),
              SizedBox(width: Space.sm.w),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _bookWeekly(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.ink2,
                    side: BorderSide(color: c.line2),
                    padding: EdgeInsets.symmetric(vertical: Space.xs.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                  ),
                  child: const Text('Weekly'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds one row per reservation, except every occurrence of the same
  /// recurring series collapses into a single [_SeriesReservationGroupRow]
  /// instead of one [_ReservationRow] each — a weekly series with many
  /// future occurrences used to render as that many separate rows with
  /// that many individual cancel buttons. A one-off booking
  /// ([AppReservation.recurringSeriesId] null) still renders exactly as
  /// before. [sorted] is assumed sorted by [AppReservation.startTime]
  /// ascending, so a series's group row lands at the position of its
  /// earliest occurrence here.
  List<Widget> _reservationRows(List<AppReservation> sorted, DateTime now) {
    final rows = <Widget>[];
    final renderedSeriesIds = <String>{};
    for (final reservation in sorted) {
      final seriesId = reservation.recurringSeriesId;
      if (seriesId == null) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: Space.xs.h),
            child: FadeSlideIn(
              key: ValueKey('reservation-${reservation.id}'),
              child: _ReservationRow(
                groupId: groupId,
                space: space,
                reservation: reservation,
                holderName: namesById[reservation.userId] ?? 'A housemate',
                isMine: myUserId != null && reservation.userId == myUserId,
                canCancel: (myUserId != null && reservation.userId == myUserId) || isAdmin,
                isActiveNow: !now.isBefore(reservation.startTime) && now.isBefore(reservation.endTime),
              ),
            ),
          ),
        );
        continue;
      }
      if (renderedSeriesIds.contains(seriesId)) continue;
      renderedSeriesIds.add(seriesId);
      final groupReservations = sorted.where((r) => r.recurringSeriesId == seriesId).toList();
      final holderId = groupReservations.first.userId;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: Space.xs.h),
          child: FadeSlideIn(
            key: ValueKey('series-group-$seriesId'),
            child: _SeriesReservationGroupRow(
              groupId: groupId,
              space: space,
              seriesId: seriesId,
              reservations: groupReservations,
              holderName: namesById[holderId] ?? 'A housemate',
              holderAvatarUrl: avatarUrlById[holderId],
              canCancel: (myUserId != null && holderId == myUserId) || isAdmin,
              myUserId: myUserId,
              isAdmin: isAdmin,
            ),
          ),
        ),
      );
    }
    return rows;
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final result = await showBookingSheet(context, groupId: groupId, space: space);
    if (result == null || !context.mounted) return;

    ref.invalidate(groupReservationsProvider(groupId));
    ref.invalidate(groupChoresProvider(groupId));

    final (_, chore) = result;
    if (context.mounted) {
      await showChorePassSheet(context, groupId: groupId, chore: chore);
    }
  }

  Future<void> _bookWeekly(BuildContext context, WidgetRef ref) async {
    final input = await showRecurringSeriesSheet(context, spaceName: space.name);
    if (input == null || !context.mounted) return;

    try {
      final result = await ref.read(groupsRepositoryProvider).createRecurringSeries(
            groupId,
            space.id,
            weekdays: input.weekdaysUtc,
            startHourUtc: input.startHourUtc,
            startMinuteUtc: input.startMinuteUtc,
            durationMinutes: input.durationMinutes,
          );
      Haptics.commit();
      ref.invalidate(groupReservationsProvider(groupId));
      ref.invalidate(groupChoresProvider(groupId));
      ref.invalidate(groupMyRecurringSeriesProvider(groupId));
      if (context.mounted) {
        await showRecurringSeriesResultSheet(context, result: result);
      }
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}

/// One booked slot on a space, with the actions available for it:
/// cancelling your own booking, or — for someone else's booking that's
/// active right now — sending an urgent access request. Neither action
/// shows for a booking that's neither yours nor currently active, same as
/// before this feature existed.
class _ReservationRow extends ConsumerStatefulWidget {
  const _ReservationRow({
    required this.groupId,
    required this.space,
    required this.reservation,
    required this.holderName,
    required this.isMine,
    required this.canCancel,
    required this.isActiveNow,
  });

  final String groupId;
  final AppSpace space;
  final AppReservation reservation;
  final String holderName;
  final bool isMine;
  /// Whether this viewer may cancel this reservation — true for the
  /// booker themself, or any admin (who may cancel anyone's booking;
  /// enforced server-side by cancel_reservation's own ownership check,
  /// this just controls whether the UI offers the action at all).
  final bool canCancel;
  final bool isActiveNow;

  @override
  ConsumerState<_ReservationRow> createState() => _ReservationRowState();
}

class _ReservationRowState extends ConsumerState<_ReservationRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${widget.holderName} · '
            '${widget.reservation.startTime.toLocalDateTimeLabel()}'
            ' – ${widget.reservation.endTime.toLocalTimeLabel()}'
            '${widget.reservation.recurringSeriesId != null ? ' · weekly' : ''}',
            style: context.text.bodySmall,
          ),
        ),
        // An admin viewing someone else's currently-active booking gets
        // both actions — "ask nicely" and "cancel outright" are
        // different tools for different situations, not a choice between
        // them.
        if (!widget.isMine && widget.isActiveNow)
          Padding(
            padding: EdgeInsets.only(right: widget.canCancel ? Space.sm.w : 0),
            child: PressFeedback(
              onTap: _busy ? null : _requestUrgentAccess,
              child: Text(
                'Ask for 5 min',
                style: context.text.bodySmall?.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (widget.canCancel)
          PressFeedback(
            onTap: _busy ? null : _cancel,
            child: Icon(Icons.close, size: 16.r, color: c.ink3),
          ),
      ],
    );
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).cancelReservation(widget.groupId, widget.reservation.id);
      Haptics.commit();
      ref.invalidate(groupReservationsProvider(widget.groupId));
      ref.invalidate(groupChoresProvider(widget.groupId));
      ref.invalidate(groupMyRecurringSeriesProvider(widget.groupId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestUrgentAccess() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).requestUrgentAccess(
            widget.groupId,
            widget.space.id,
            widget.reservation.id,
          );
      Haptics.commit();
      if (mounted) showAppSnackBar(context, 'Sent. ${widget.holderName} has been notified.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Every occurrence of one recurring booking series within a space,
/// collapsed into a single summary row — the fix for the bug where a
/// weekly series with many future occurrences rendered as that many
/// separate [_ReservationRow]s. Collapsed by default; expanding shows
/// each occurrence as its own unchanged [_ReservationRow] (so cancelling
/// a single occurrence, or asking for urgent access on one that's
/// currently active, both keep working exactly as before). The "Cancel
/// series" action here calls the exact same [cancelRecurringSeries] used
/// by [_RecurringSeriesRow] elsewhere on this page.
class _SeriesReservationGroupRow extends ConsumerStatefulWidget {
  const _SeriesReservationGroupRow({
    required this.groupId,
    required this.space,
    required this.seriesId,
    required this.reservations,
    required this.holderName,
    required this.holderAvatarUrl,
    required this.canCancel,
    required this.myUserId,
    required this.isAdmin,
  });

  final String groupId;
  final AppSpace space;
  final String seriesId;
  /// Every occurrence of this series in this space, sorted by
  /// [AppReservation.startTime] ascending. All belong to the same booker
  /// ([AppReservation.userId]), since a series has a single owner.
  final List<AppReservation> reservations;
  final String holderName;
  final String? holderAvatarUrl;
  /// Whether this viewer may cancel the whole series — same booker-or-admin
  /// rule as an individual [_ReservationRow.canCancel].
  final bool canCancel;
  final String? myUserId;
  final bool isAdmin;

  @override
  ConsumerState<_SeriesReservationGroupRow> createState() => _SeriesReservationGroupRowState();
}

class _SeriesReservationGroupRowState extends ConsumerState<_SeriesReservationGroupRow> {
  bool _expanded = false;
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now().toUtc();
    final upcoming = widget.reservations.where((r) => r.startTime.isAfter(now)).length;
    final weekdayNumbers = widget.reservations.map((r) => r.startTime.toLocal().weekday).toSet().toList()
      ..sort();
    // AppReservation.startTime.weekday is Dart's 1=Monday..7=Sunday;
    // _weekdayShortLabel expects the backend's 0=Monday..6=Sunday.
    final dayLabels = weekdayNumbers.map((d) => _weekdayShortLabel(d - 1)).join(', ');
    final first = widget.reservations.first;
    final timeLabel = '${first.startTime.toLocalTimeLabel()} – ${first.endTime.toLocalTimeLabel()}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.sm.r),
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
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.sm.h),
              child: Row(
                children: [
                  Avatar(name: widget.holderName, photoUrl: widget.holderAvatarUrl, size: 22.r),
                  SizedBox(width: Space.sm.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.holderName} · $dayLabels · $timeLabel',
                          style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            const _RecurringBadge(),
                            SizedBox(width: Space.sm.w),
                            Expanded(
                              child: Text(
                                '$upcoming upcoming',
                                style: context.text.bodySmall?.copyWith(color: c.ink3),
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
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18.r,
                    color: c.ink3,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: c.line),
            Padding(
              padding: EdgeInsets.fromLTRB(Space.md.w, Space.sm.h, Space.md.w, Space.sm.h),
              child: Column(
                children: [
                  for (final reservation in widget.reservations)
                    Padding(
                      padding: EdgeInsets.only(bottom: Space.xs.h),
                      child: _ReservationRow(
                        groupId: widget.groupId,
                        space: widget.space,
                        reservation: reservation,
                        holderName: widget.holderName,
                        isMine: widget.myUserId != null && reservation.userId == widget.myUserId,
                        canCancel:
                            (widget.myUserId != null && reservation.userId == widget.myUserId) || widget.isAdmin,
                        isActiveNow: !now.isBefore(reservation.startTime) && now.isBefore(reservation.endTime),
                      ),
                    ),
                  if (widget.canCancel)
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _cancelling ? null : _cancelSeries,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.call.solid,
                          side: BorderSide(color: c.line2),
                          padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                        ),
                        child: _cancelling
                            ? SizedBox(
                                width: 14.r,
                                height: 14.r,
                                child: CircularProgressIndicator(strokeWidth: 2, color: c.call.solid),
                              )
                            : const Text('Cancel series'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancelSeries() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(groupsRepositoryProvider).cancelRecurringSeries(widget.groupId, widget.seriesId);
      Haptics.commit();
      ref.invalidate(groupReservationsProvider(widget.groupId));
      ref.invalidate(groupChoresProvider(widget.groupId));
      ref.invalidate(groupMyRecurringSeriesProvider(widget.groupId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }
}

/// One of the caller's own recurring series: what it books and a way to
/// cancel the whole thing. Individual occurrences are cancelled from
/// their own row in [_SpaceCard] instead — this row is series-scoped only.
class _RecurringSeriesRow extends ConsumerStatefulWidget {
  const _RecurringSeriesRow({required this.groupId, required this.series, required this.spaceName});

  final String groupId;
  final AppRecurringSeries series;
  final String spaceName;

  @override
  ConsumerState<_RecurringSeriesRow> createState() => _RecurringSeriesRowState();
}

class _RecurringSeriesRowState extends ConsumerState<_RecurringSeriesRow> {
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.series;
    final dayLabels = s.weekdays.map((d) => _weekdayShortLabel(d)).join(', ');
    // The series's own hour/minute are UTC; a local hour:minute is shown
    // by combining them with today's date purely for display formatting.
    final sampleUtc = DateTime.now().toUtc();
    final sampleStart = DateTime.utc(
      sampleUtc.year,
      sampleUtc.month,
      sampleUtc.day,
      s.startHourUtc,
      s.startMinuteUtc,
    );
    final sampleEnd = sampleStart.add(Duration(minutes: s.durationMinutes));

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
                Text(
                  widget.spaceName,
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 1.h),
                Text(
                  '$dayLabels · ${sampleStart.toLocalTimeLabel()} – ${sampleEnd.toLocalTimeLabel()}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(width: Space.sm.w),
          OutlinedButton(
            onPressed: _cancelling ? null : _cancelSeries,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.call.solid,
              side: BorderSide(color: c.line2),
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
            ),
            child: _cancelling
                ? SizedBox(
                    width: 14.r,
                    height: 14.r,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.call.solid),
                  )
                : const Text('Cancel series'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelSeries() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(groupsRepositoryProvider).cancelRecurringSeries(widget.groupId, widget.series.id);
      Haptics.commit();
      ref.invalidate(groupReservationsProvider(widget.groupId));
      ref.invalidate(groupChoresProvider(widget.groupId));
      ref.invalidate(groupMyRecurringSeriesProvider(widget.groupId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }
}

const _weekdayShortLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekdayShortLabel(int weekday) => _weekdayShortLabels[weekday];

/// In-app banner for a pending urgent access request addressed to the
/// current user — same visual shape as GroupDetailPage's nudge banner,
/// kept local to this screen since that's where the context (which
/// space, whose booking) actually lives.
class _UrgentAccessBanner extends StatelessWidget {
  const _UrgentAccessBanner({
    required this.request,
    required this.requesterName,
    required this.spaceName,
    required this.onDismiss,
  });

  final UrgentAccessRequest request;
  final String requesterName;
  final String spaceName;
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
                '$requesterName needs $spaceName for 5 minutes.',
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

/// The single most-urgent chore of the caller's own, shown as the mockup's
/// gradient-tinted hero card instead of a plain row — any further chores
/// of the caller's own render as plain [_ChoreRow]s underneath.
class _YourNextChoreCard extends ConsumerWidget {
  const _YourNextChoreCard({required this.groupId, required this.chore});

  final String groupId;
  final AppChore chore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
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
            'CHORE',
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
              onPressed: () => _markDone(context, ref),
              child: const Text('Mark done'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupsRepositoryProvider).markChoreDone(chore.id);
      Haptics.commit();
      ref.invalidate(groupChoresProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}

class _ChoreRow extends ConsumerWidget {
  const _ChoreRow({required this.groupId, required this.chore, required this.isWeekly});

  final String groupId;
  final AppChore chore;
  final bool isWeekly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chore.template, style: context.text.bodyLarge),
                SizedBox(height: Space.xs.h),
                Row(
                  children: [
                    if (isWeekly) ...[
                      const _RecurringBadge(),
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
            onPressed: () => _markDone(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink2,
              side: BorderSide(color: c.line2),
              padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupsRepositoryProvider).markChoreDone(chore.id);
      Haptics.commit();
      ref.invalidate(groupChoresProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
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
                      const _RecurringBadge(),
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

/// The small "Weekly" pill shown next to a chore that came from a
/// recurring booking series, rather than a one-off booking.
class _RecurringBadge extends StatelessWidget {
  const _RecurringBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Space.sm.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.pill.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5.r, height: 5.r, decoration: BoxDecoration(color: c.ink3, shape: BoxShape.circle)),
          SizedBox(width: 4.w),
          Text(
            'Weekly',
            style: context.text.bodySmall?.copyWith(color: c.ink2, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
