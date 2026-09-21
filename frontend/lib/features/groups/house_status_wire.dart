import '../../theme/app_colors.dart';

/// Maps [HouseStatus] to/from the snake_case strings the backend's
/// `HouseStatus` enum serializes to.
extension HouseStatusWire on HouseStatus {
  String get wireValue => switch (this) {
        HouseStatus.openToChat => 'open_to_chat',
        HouseStatus.deepFocus => 'deep_focus',
        HouseStatus.inCall => 'in_call',
        HouseStatus.sleepingEarly => 'sleeping_early',
        HouseStatus.away => 'away',
      };

  static HouseStatus fromWire(String value) =>
      HouseStatus.values.firstWhere((status) => status.wireValue == value);
}

/// Per-status duration policy (the Time Limits spec). Mirrors
/// `STATUS_DURATION_RULES` in app/schemas/status.py — the backend is the
/// actual enforcement point (a client can't be trusted to only ever send
/// one of these), this copy only drives which presets the picker offers.
/// Keep both in sync, the same way the `HouseStatus` values themselves
/// already have to stay in sync across schemas/status.py, this file, and
/// app_colors.dart.
class StatusDurationRule {
  const StatusDurationRule({
    required this.defaultMinutes,
    required this.allowedMinutes,
  });

  final int defaultMinutes;
  final List<int> allowedMinutes;
}

/// One uniform rule for all four temporary statuses — the client
/// simplified this from the original per-status preset lists: 30 minutes
/// to 8 hours, in 30-minute steps, no 15-minute option. Open to Chat has
/// no entry in [statusDurationRules] at all, which is what makes it show
/// no duration row.
const _uniformTemporaryStatusRule = StatusDurationRule(
  defaultMinutes: 30,
  allowedMinutes: [30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480],
);

const Map<HouseStatus, StatusDurationRule> statusDurationRules = {
  HouseStatus.inCall: _uniformTemporaryStatusRule,
  HouseStatus.deepFocus: _uniformTemporaryStatusRule,
  HouseStatus.sleepingEarly: _uniformTemporaryStatusRule,
  HouseStatus.away: _uniformTemporaryStatusRule,
};

/// "30m" / "1h" / "1.5h" / "8h" — the uniform 30-minute-step scale means
/// odd multiples of 30 (90, 150, 210, ...) land on a half hour, so this
/// has to handle a fractional value, not just whole hours.
String formatDurationMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  if (minutes % 60 == 0) return '${minutes ~/ 60}h';
  return '${minutes / 60}h';
}
