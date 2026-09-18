/// Mirrors the backend's `NudgeType` enum (app/schemas/nudge.py). Adding a
/// preset there means adding one case here too — everything else (the
/// one-tap button list, the send call) reads off this enum.
enum NudgeType {
  quietPulse('quiet_pulse'),
  packageArrived('package_arrived'),
  frontDoorUnlocked('front_door_unlocked'),
  sinkFull('sink_full');

  const NudgeType(this.wireValue);

  final String wireValue;

  static NudgeType fromWire(String value) =>
      NudgeType.values.firstWhere((type) => type.wireValue == value);
}

/// Label + icon for the one-tap preset buttons. [NudgeType.quietPulse] isn't
/// here — it gets its own sheet (duration picker), not a one-tap button.
const presetNudgeTypes = [
  NudgeType.packageArrived,
  NudgeType.frontDoorUnlocked,
  NudgeType.sinkFull,
];

extension NudgePresetLabel on NudgeType {
  String get presetLabel => switch (this) {
        NudgeType.quietPulse => 'Quiet, {duration} min',
        NudgeType.packageArrived => 'Package arrived',
        NudgeType.frontDoorUnlocked => 'Front door unlocked',
        NudgeType.sinkFull => 'Sink full',
      };
}
