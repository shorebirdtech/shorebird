/// Why a rollout-speed sample does not qualify for aggregate statistics.
/// Ineligible samples are still returned — flagged, never dropped.
enum RolloutIneligibleReason {
  /// The patch's parent release never reached the minimum share of its target
  /// audience, so the patch's audience is not representative.
  releaseBelowFloor._('release_below_floor'),

  /// The sample's audience never had enough devices for a stable share.
  audienceTooSmall._('audience_too_small'),

  /// The rollout was already past the start threshold at the edge of the data
  /// window, so its transit times would measure the window, not the rollout.
  leftCensored._('left_censored');

  const RolloutIneligibleReason._(this.value);

  /// Creates a RolloutIneligibleReason from a json value.
  factory RolloutIneligibleReason.fromJson(String json) {
    return RolloutIneligibleReason.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown RolloutIneligibleReason value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static RolloutIneligibleReason? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return RolloutIneligibleReason.fromJson(json);
  }

  /// The value of the enum.  This is the exact value
  /// from the OpenAPI spec and will be used for network transport.
  final String value;

  /// Converts the enum to its json value.
  String toJson() => value;

  /// Returns the string form of the enum.
  @override
  String toString() => value;
}
