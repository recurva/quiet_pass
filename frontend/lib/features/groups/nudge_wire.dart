/// Mirrors the backend's `NudgeType` enum (app/schemas/nudge.py). Adding a
/// preset there means adding one case here too — everything else (the
/// one-tap button list, the send call) reads off this enum.
enum NudgeType {
  quietPulse('quiet_pulse'),
  packageArrived('package_arrived'),
  frontDoorUnlocked('front_door_unlocked'),
  sinkFull('sink_full'),
  custom('custom');

  const NudgeType(this.wireValue);

  final String wireValue;

  static NudgeType fromWire(String value) =>
      NudgeType.values.firstWhere((type) => type.wireValue == value);
}

/// Matches CUSTOM_NUDGE_MESSAGE_MAX_LENGTH in app/schemas/nudge.py.
const customNudgeMessageMaxLength = 140;

/// Label + icon for the one-tap preset buttons. Neither [NudgeType.quietPulse]
/// nor [NudgeType.custom] is here — each gets its own sheet (a duration
/// picker, a text field) instead of a plain one-tap button.
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
        NudgeType.custom => 'Custom',
      };
}
