/// Whether a member is marked home for dinner tonight, or staying out.
/// Mirrors the backend's `DinnerStatus` enum (app/models/dinner_headcount.py).
enum DinnerStatus { home, stayingOut }

extension DinnerStatusWire on DinnerStatus {
  String get wireValue => switch (this) {
        DinnerStatus.home => 'home',
        DinnerStatus.stayingOut => 'staying_out',
      };

  static DinnerStatus fromWire(String value) =>
      DinnerStatus.values.firstWhere((status) => status.wireValue == value);
}
