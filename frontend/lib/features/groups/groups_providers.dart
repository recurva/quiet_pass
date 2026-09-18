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

/// Refetches the member list whenever a `member_joined` event arrives —
/// previously nothing did this at all, so an already-open session only
/// learned about a new housemate by being fully restarted.
final groupMembersLiveRefreshProvider = Provider.autoDispose.family<void, String>((ref, groupId) {
  ref.listen(groupMemberJoinedEventsProvider(groupId), (previous, next) {
    next.whenData((_) => ref.invalidate(groupMembersProvider(groupId)));
  });
});

final groupMemberJoinedEventsProvider =
    StreamProvider.autoDispose.family<void, String>((ref, groupId) {
  return ref.watch(groupStatusClientProvider(groupId)).memberJoined;
});
