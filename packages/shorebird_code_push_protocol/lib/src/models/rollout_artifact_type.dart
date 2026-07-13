/// The kind of artifact a rollout-speed sample describes.
enum RolloutArtifactType {
  /// A store release; its adoption share is measured over all of the app's
  /// devices on the platform(s) the release was observed on.
  release._('release'),

  /// A Shorebird patch; its adoption share is measured over the distinct
  /// devices on its release.
  patch._('patch');

  const RolloutArtifactType._(this.value);

  /// Creates a RolloutArtifactType from a json value.
  factory RolloutArtifactType.fromJson(String json) {
    return RolloutArtifactType.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown RolloutArtifactType value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static RolloutArtifactType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return RolloutArtifactType.fromJson(json);
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
