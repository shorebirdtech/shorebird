/// The status of a release.
enum ReleaseStatus {
  /// The release has been created, but not all platform artifacts have been
  /// uploaded.
  draft._('draft'),

  /// All platform artifacts have been uploaded for this release.
  active._('active');

  const ReleaseStatus._(this.value);

  /// Creates a ReleaseStatus from a json value.
  factory ReleaseStatus.fromJson(String json) {
    return ReleaseStatus.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException('Unknown ReleaseStatus value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ReleaseStatus? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ReleaseStatus.fromJson(json);
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
