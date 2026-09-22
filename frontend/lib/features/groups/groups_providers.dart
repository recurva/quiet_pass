import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'group_models.dart';
import 'group_status_client.dart';
import 'groups_repository.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(apiClientProvider));
});

/// Fetches (and, on the backend, provisions) the signed-in user's row.
final currentBackendUserProvider = FutureProvider<AppUser>((ref) {
  return ref.watch(groupsRepositoryProvider).fetchOrCreateMe();
});

final myGroupsProvider = FutureProvider<List<AppGroup>>((ref) {
  return ref.watch(groupsRepositoryProvider).fetchMyGroups();
});

final groupMembersProvider =
    FutureProvider.autoDispose.family<List<HouseMember>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).fetchHouseMembers(groupId);
});

/// One WebSocket connection per open group-detail screen. `autoDispose`
/// closes it (via [GroupStatusClient.dispose]) once nothing's watching it
/// anymore, i.e. when the screen is popped.
final groupStatusClientProvider =
    Provider.autoDispose.family<GroupStatusClient, String>((ref, groupId) {
  final client = GroupStatusClient(groupId: groupId);
  client.connect();
  ref.onDispose(client.dispose);
  return client;
});

final groupStatusesProvider =
    StreamProvider.autoDispose.family<Map<String, MemberStatus>, String>((ref, groupId) {
  return ref.watch(groupStatusClientProvider(groupId)).statuses;
});

/// The seam for a future FCM swap: the group-detail screen only ever watches
/// this provider for nudges, never [GroupStatusClient] directly. Today it's
/// backed by the same WebSocket as [groupStatusesProvider]; later, pointing
/// this at an FCM-backed `Stream<AppNudge>` instead is the entire change —
/// the screen's `ref.watch(groupNudgesProvider(...))` call doesn't move.
final groupNudgesProvider = StreamProvider.autoDispose.family<AppNudge, String>((ref, groupId) {
  return ref.watch(groupStatusClientProvider(groupId)).nudges;
});

final groupSpacesProvider = FutureProvider.autoDispose.family<List<AppSpace>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).fetchSpaces(groupId);
});

final groupReservationsProvider =
    FutureProvider.autoDispose.family<List<AppReservation>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).fetchReservations(groupId);
});

final groupChoresProvider = FutureProvider.autoDispose.family<List<AppChore>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).fetchChores(groupId);
});

/// Refetches the reservation (and chore) lists whenever a `reservation`
/// event arrives over the WebSocket — simpler and just as correct as
/// merging the event into local state by hand, given how small a group's
/// reservation list is.
final groupReservationsLiveRefreshProvider = Provider.autoDispose.family<void, String>((ref, groupId) {
  ref.listen(groupReservationEventsProvider(groupId), (previous, next) {
    next.whenData((_) {
      ref.invalidate(groupReservationsProvider(groupId));
      ref.invalidate(groupChoresProvider(groupId));
    });
  });
});

final groupReservationEventsProvider =
    StreamProvider.autoDispose.family<AppReservation, String>((ref, groupId) {
  return ref.watch(groupStatusClientProvider(groupId)).reservations;
});

/// Refetches the member list whenever a `member_joined` or `member_left`
/// event arrives — previously neither existed at all, so an already-open
/// session only learned about a new housemate, or one whose account was
/// deleted, by being fully restarted.
final groupMembersLiveRefreshProvider = Provider.autoDispose.family<void, String>((ref, groupId) {
  ref.listen(groupMemberListChangedEventsProvider(groupId), (previous, next) {
    next.whenData((_) => ref.invalidate(groupMembersProvider(groupId)));
  });
});

final groupMemberListChangedEventsProvider =
    StreamProvider.autoDispose.family<void, String>((ref, groupId) {
  return ref.watch(groupStatusClientProvider(groupId)).memberListChanged;
});

/// Unacknowledged nudges for a group — deliberately **not** `autoDispose`.
/// A nudge must stay visible until the user dismisses it (the spec's whole
/// point), including across leaving and returning to this screen; storing
/// the list in the page's own `State` meant it reset every time the widget
/// was torn down and recreated (e.g. navigating away and back), which is
/// exactly the "flash and vanish" behavior the persistent inbox was meant
/// to fix in the first place.
///
/// Side effect worth knowing: because this provider never disposes, its
/// `ref.listen` below keeps [groupNudgesProvider] (and the WebSocket
/// connection under it) alive for as long as the app runs, not just while
/// the group screen is open — a reasonable tradeoff for "don't miss a
/// nudge," but a real change from every other `autoDispose` provider in
/// this file, which all close their WebSocket the moment nothing's
/// watching them.
class PendingNudgesNotifier extends FamilyNotifier<List<AppNudge>, String> {
  @override
  List<AppNudge> build(String groupId) {
    ref.listen(groupNudgesProvider(groupId), (previous, next) {
      final nudge = next.valueOrNull;
      if (nudge == null) return;
      if (state.any((n) => n.id == nudge.id)) return;
      state = [...state, nudge];
    });
    return [];
  }

  void dismiss(String nudgeId) {
    state = state.where((n) => n.id != nudgeId).toList();
  }
}

final groupPendingNudgesProvider =
    NotifierProvider.family<PendingNudgesNotifier, List<AppNudge>, String>(
  PendingNudgesNotifier.new,
);
