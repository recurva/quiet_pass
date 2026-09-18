import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'booking_sheet.dart';
import 'chore_pass_sheet.dart';
import 'group_models.dart';
import 'groups_providers.dart';

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

    final spacesAsync = ref.watch(groupSpacesProvider(groupId));
    final reservationsAsync = ref.watch(groupReservationsProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final choresAsync = ref.watch(groupChoresProvider(groupId));
    final me = ref.watch(currentBackendUserProvider).valueOrNull;

    final namesById = <String, String>{
      for (final member in membersAsync.valueOrNull ?? const [])
        member.user.id: member.user.displayName,
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
                  child: Text('$error', style: context.text.bodySmall?.copyWith(color: c.ink3)),
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
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: Space.base.h),
              Text(
                'YOUR CHORES',
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
                  child: Text('$error', style: context.text.bodySmall?.copyWith(color: c.ink3)),
                ),
                data: (chores) {
                  final mine = me == null
                      ? const <AppChore>[]
                      : chores.where((chore) => chore.userId == me.id && !chore.done).toList();
                  if (mine.isEmpty) {
                    return Text(
                      'Nothing pending.',
                      style: context.text.bodySmall?.copyWith(color: c.ink3),
                    );
                  }
                  return Column(
                    children: [
                      for (final chore in mine)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.sm.h),
                          child: _ChoreRow(groupId: groupId, chore: chore),
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
  });

  final String groupId;
  final AppSpace space;
  final List<AppReservation> reservations;
  final Map<String, String> namesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sorted = [...reservations]..sort((a, b) => a.startTime.compareTo(b.startTime));

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                space.name,
                style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              OutlinedButton(
                onPressed: () => _book(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink2,
                  side: BorderSide(color: c.line2),
                  padding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.xs.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
                ),
                child: const Text('Book'),
              ),
            ],
          ),
          if (sorted.isEmpty) ...[
            SizedBox(height: Space.xs.h),
            Text('Nothing booked.', style: context.text.bodySmall?.copyWith(color: c.ink3)),
          ] else ...[
            SizedBox(height: Space.sm.h),
            for (final reservation in sorted)
              Padding(
                padding: EdgeInsets.only(bottom: Space.xs.h),
                child: Text(
                  '${namesById[reservation.userId] ?? 'A housemate'} · '
                  '${reservation.startTime.toLocalDateTimeLabel()}'
                  ' – ${reservation.endTime.toLocalTimeLabel()}',
                  style: context.text.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
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
}

class _ChoreRow extends ConsumerWidget {
  const _ChoreRow({required this.groupId, required this.chore});

  final String groupId;
  final AppChore chore;

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
                SizedBox(height: 1.h),
                Text(
                  isDue ? 'Due now' : 'Due ${chore.dueAt.toLocalDateTimeLabel()}',
                  style: context.text.bodySmall?.copyWith(
                    color: isDue ? c.call.solid : c.ink3,
                  ),
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
      ref.invalidate(groupChoresProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}
