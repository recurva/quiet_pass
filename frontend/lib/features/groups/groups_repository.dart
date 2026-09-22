import '../../core/api_client.dart';
import '../../theme/app_colors.dart';
import 'group_models.dart';
import 'house_status_wire.dart';
import 'nudge_wire.dart';

/// Wraps the backend's user/group endpoints for the Flutter side. The
/// caller's identity always comes from the Bearer token ApiClient attaches,
/// never from a parameter here.
class GroupsRepository {
  GroupsRepository(this._client);

  final ApiClient _client;

  /// GET /users/me: fetches the caller's User row, provisioning it
  /// server-side on first call after sign-in.
  Future<AppUser> fetchOrCreateMe() async {
    final json = await _client.get('/users/me');
    return AppUser.fromJson(json as Map<String, dynamic>);
  }

  /// POST /auth/sign-in: called once, right after Firebase OTP
  /// verification succeeds, for both the Sign In and Sign Up screens
  /// alike. [displayName] is only ever used server-side if this turns
  /// out to be a genuinely new phone number — an existing user's name is
  /// never touched by this call, regardless of what's passed. The
  /// returned `isNew` is the actual source of truth for new-vs-returning,
  /// not which screen the caller used.
  Future<(AppUser, bool)> signIn({String? displayName}) async {
    final json = await _client.post(
      '/auth/sign-in',
      body: {if (displayName != null) 'display_name': displayName},
    );
    final map = json as Map<String, dynamic>;
    return (
      AppUser.fromJson(map['user'] as Map<String, dynamic>),
      map['is_new'] as bool,
    );
  }

  /// GET /auth/phone-exists: lets the Sign Up screen reject an
  /// already-registered number up front, before spending an OTP on it,
  /// instead of only finding out afterward — see SignUpPage's _submit.
  /// Unauthenticated (no Firebase user exists yet at this point).
  Future<bool> checkPhoneExists(String phoneNumber) async {
    final json = await _client.getUnauthenticated(
      '/auth/phone-exists?phone_number=${Uri.encodeQueryComponent(phoneNumber)}',
    );
    return (json as Map<String, dynamic>)['exists'] as bool;
  }

  Future<List<AppGroup>> fetchMyGroups() async {
    final json = await _client.get('/groups/mine');
    return (json as List<dynamic>)
        .map((entry) => AppGroup.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<AppGroup> createGroup(String name) async {
    final json = await _client.post('/groups', body: {'name': name});
    return AppGroup.fromJson(json as Map<String, dynamic>);
  }

  Future<void> joinGroup(String inviteCode) async {
    await _client.post('/groups/join', body: {'invite_code': inviteCode});
  }

  Future<List<AppMembership>> fetchMembers(String groupId) async {
    final json = await _client.get('/groups/$groupId/members');
    return (json as List<dynamic>)
        .map((entry) => AppMembership.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<AppUser> fetchUser(String userId) async {
    final json = await _client.get('/users/$userId');
    return AppUser.fromJson(json as Map<String, dynamic>);
  }

  /// Members of a group, each paired with their profile. N+1 over
  /// GET /users/{id}, run in parallel; fine for typical house sizes.
  Future<List<HouseMember>> fetchHouseMembers(String groupId) async {
    final memberships = await fetchMembers(groupId);
    final users = await Future.wait(memberships.map((m) => fetchUser(m.userId)));
    return [
      for (var i = 0; i < memberships.length; i++)
        HouseMember(user: users[i], role: memberships[i].role),
    ];
  }

  /// [durationMinutes] is ignored server-side for [HouseStatus.openToChat]
  /// (indefinite, no duration concept) and, for every other status, must be
  /// omitted to take that status's default or be one of its allowed
  /// presets — see `statusDurationRules` and the backend's
  /// `STATUS_DURATION_RULES`, which is the actual enforcement point.
  Future<void> setMyStatus(String groupId, HouseStatus status, {int? durationMinutes}) async {
    await _client.put(
      '/groups/$groupId/status',
      body: {
        'status': status.wireValue,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      },
    );
  }

  /// PATCH /users/me: the only self-editable field today. Called at
  /// signup (see OtpFlowController) and from the profile screen's edit.
  Future<AppUser> updateDisplayName(String displayName) async {
    final json = await _client.patch('/users/me', body: {'display_name': displayName});
    return AppUser.fromJson(json as Map<String, dynamic>);
  }

  /// DELETE /users/me: deletes the account from both Firebase Auth and
  /// Postgres server-side (see the backend's delete_current_user). The
  /// caller is still responsible for signing out of Firebase locally
  /// afterward — this only handles the two server-side deletions.
  Future<void> deleteAccount() async {
    await _client.delete('/users/me');
  }

  /// Sends a nudge. [durationMinutes] is required for [NudgeType.quietPulse]
  /// and must be omitted for every preset — the caller only ever supplies a
  /// type, never free text; the server renders the actual wording.
  Future<void> sendNudge(String groupId, NudgeType type, {int? durationMinutes}) async {
    await _client.post(
      '/groups/$groupId/nudges',
      body: {
        'type': type.wireValue,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      },
    );
  }

  /// Registers (or re-registers) this device's FCM token with the backend,
  /// so nudges reach it via push even when the app isn't open. Safe to call
  /// repeatedly — the backend upserts by token.
  Future<void> registerDeviceToken(String token, {String platform = 'android'}) async {
    await _client.post('/device-tokens', body: {'token': token, 'platform': platform});
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _client.delete('/device-tokens?token=${Uri.encodeQueryComponent(token)}');
  }

  Future<List<AppSpace>> fetchSpaces(String groupId) async {
    final json = await _client.get('/groups/$groupId/spaces');
    return (json as List<dynamic>)
        .map((entry) => AppSpace.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppReservation>> fetchReservations(String groupId) async {
    final json = await _client.get('/groups/$groupId/reservations');
    return (json as List<dynamic>)
        .map((entry) => AppReservation.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  /// Books a space. [startTime] is sent as UTC regardless of what timezone
  /// it was constructed in locally — the backend only ever deals in UTC.
  Future<(AppReservation, AppChore)> createReservation(
    String groupId,
    String spaceId,
    DateTime startTime,
    int durationMinutes,
  ) async {
    final json = await _client.post(
      '/groups/$groupId/spaces/$spaceId/reservations',
      body: {
        'start_time': startTime.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
      },
    );
    final map = json as Map<String, dynamic>;
    return (
      AppReservation.fromJson(map['reservation'] as Map<String, dynamic>),
      AppChore.fromJson(map['chore'] as Map<String, dynamic>),
    );
  }

  Future<List<AppChore>> fetchChores(String groupId) async {
    final json = await _client.get('/groups/$groupId/chores');
    return (json as List<dynamic>)
        .map((entry) => AppChore.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<void> markChoreDone(String choreId) async {
    await _client.patch('/chores/$choreId/done');
  }
}
