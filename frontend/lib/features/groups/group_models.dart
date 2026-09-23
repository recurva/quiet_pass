import '../../theme/app_colors.dart';
import 'house_status_wire.dart';
import 'nudge_wire.dart';

/// Thin client-side mirrors of the backend's UserRead / GroupRead schemas.
class AppUser {
  const AppUser({
    required this.id,
    required this.phoneNumber,
    required this.displayName,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        phoneNumber: json['phone_number'] as String,
        displayName: json['display_name'] as String,
      );

  final String id;
  final String phoneNumber;
  final String displayName;
}

class AppGroup {
  const AppGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
  });

  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String,
      );

  final String id;
  final String name;
  final String inviteCode;
}

class AppMembership {
  const AppMembership({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.role,
  });

  factory AppMembership.fromJson(Map<String, dynamic> json) => AppMembership(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        groupId: json['group_id'] as String,
        role: json['role'] as String,
      );

  final String id;
  final String userId;
  final String groupId;
  final String role;
}

/// A live status entry as broadcast over the group WebSocket (or read via
/// the plain REST status endpoints). Mirrors the backend's `StatusRead`.
///
/// [status] is never null on the wire — an expired or never-set status
/// resolves to [HouseStatus.openToChat] server-side (the Time Limits spec's
/// "open by default" rule), so there's no separate "no status" state to
/// model here. [expiresAt] is null exactly when the status is Open to
/// Chat, which never expires.
class MemberStatus {
  const MemberStatus({required this.userId, required this.status, required this.expiresAt});

  factory MemberStatus.fromJson(Map<String, dynamic> json) {
    final rawExpiresAt = json['expires_at'] as String?;
    return MemberStatus(
      userId: json['user_id'] as String,
      status: HouseStatusWire.fromWire(json['status'] as String),
      expiresAt: rawExpiresAt == null ? null : DateTime.parse(rawExpiresAt).toUtc(),
    );
  }

  final String userId;
  final HouseStatus status;
  final DateTime? expiresAt;

  /// The status actually shown, accounting for a timer that has lapsed
  /// since this entry was last fetched or broadcast: nothing server-side
  /// pushes an update at the exact expiry moment (Redis just lets the key
  /// silently expire), so a client holding a stale [MemberStatus] has to
  /// notice the crossover itself by comparing [expiresAt] to now.
  HouseStatus effectiveStatus(DateTime now) {
    if (expiresAt != null && !now.isBefore(expiresAt!)) return HouseStatus.openToChat;
    return status;
  }
}

/// A housemate combined with their group role, for the detail screen.
class HouseMember {
  const HouseMember({required this.membershipId, required this.user, required this.role});

  final String membershipId;
  final AppUser user;
  final String role;
}

/// A nudge as broadcast over the group WebSocket. Mirrors the backend's
/// `NudgeRead` — notice there's no sender field: the backend's response
/// schema structurally has no sender to leak, and this mirror doesn't
/// invent one.
class AppNudge {
  const AppNudge({
    required this.id,
    required this.groupId,
    required this.type,
    required this.message,
    required this.durationMinutes,
  });

  factory AppNudge.fromJson(Map<String, dynamic> json) => AppNudge(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        type: NudgeType.fromWire(json['type'] as String),
        message: json['message'] as String,
        durationMinutes: json['duration_minutes'] as int?,
      );

  final String id;
  final String groupId;
  final NudgeType type;
  final String message;
  final int? durationMinutes;
}

/// A bookable space within a group (Living Room, Kitchen, Main Desk, ...).
class AppSpace {
  const AppSpace({required this.id, required this.groupId, required this.name});

  factory AppSpace.fromJson(Map<String, dynamic> json) => AppSpace(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        name: json['name'] as String,
      );

  final String id;
  final String groupId;
  final String name;
}

/// A booking of a space. Reservations are NOT anonymous — [userId] is who
/// booked it, shown to the group, unlike a nudge's sender.
///
/// [startTime]/[endTime] are always normalized to UTC on parse
/// (`.toUtc()`); every call site converts `.toLocal()` only at the point
/// of display, so "4:00" shown to the user always means their own device's
/// 4:00, never a silently-mismatched server time.
class AppReservation {
  const AppReservation({
    required this.id,
    required this.groupId,
    required this.spaceId,
    required this.userId,
    required this.startTime,
    required this.endTime,
  });

  factory AppReservation.fromJson(Map<String, dynamic> json) => AppReservation(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        spaceId: json['space_id'] as String,
        userId: json['user_id'] as String,
        startTime: DateTime.parse(json['start_time'] as String).toUtc(),
        endTime: DateTime.parse(json['end_time'] as String).toUtc(),
      );

  final String id;
  final String groupId;
  final String spaceId;
  final String userId;
  final DateTime startTime;
  final DateTime endTime;
}

/// The clean-up task attached to a reservation, assigned to whoever booked
/// it. [dueAt] is when the reservation ends; nothing schedules or "fires"
/// this chore at that moment — it's created immediately at booking time
/// and simply carries a due time the UI checks against `now()` on render
/// (see the "due now" vs "upcoming" split in the chore widgets).
class AppChore {
  const AppChore({
    required this.id,
    required this.reservationId,
    required this.userId,
    required this.template,
    required this.dueAt,
    required this.done,
  });

  factory AppChore.fromJson(Map<String, dynamic> json) => AppChore(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        userId: json['user_id'] as String,
        template: json['template'] as String,
        dueAt: DateTime.parse(json['due_at'] as String).toUtc(),
        done: json['done'] as bool,
      );

  final String id;
  final String reservationId;
  final String userId;
  final String template;
  final DateTime dueAt;
  final bool done;
}
