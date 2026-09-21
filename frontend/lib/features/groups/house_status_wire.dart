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

const Map<HouseStatus, StatusDurationRule> statusDurationRules = {
  HouseStatus.inCall: StatusDurationRule(defaultMinutes: 30, allowedMinutes: [15, 30, 60, 120]),
  HouseStatus.deepFocus: StatusDurationRule(defaultMinutes: 120, allowedMinutes: [60, 120, 240]),
  HouseStatus.sleepingEarly:
      StatusDurationRule(defaultMinutes: 480, allowedMinutes: [360, 480, 600]),
  HouseStatus.away: StatusDurationRule(defaultMinutes: 240, allowedMinutes: [120, 240, 480, 1440]),
};

/// "15m" / "1h" / "2h" / "24h" — every duration in [statusDurationRules] is
/// a whole number of minutes or a whole number of hours, so this never
/// needs to render a fractional value.
String formatDurationMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h';
}
