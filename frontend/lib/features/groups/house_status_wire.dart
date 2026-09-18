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

/// The three TTL options the backend's `StatusTtl` enum allows, in seconds.
enum StatusTtlOption {
  twoHours(7200, '2h'),
  fourHours(14400, '4h'),
  eightHours(28800, '8h');

  const StatusTtlOption(this.seconds, this.label);

  final int seconds;
  final String label;
}
