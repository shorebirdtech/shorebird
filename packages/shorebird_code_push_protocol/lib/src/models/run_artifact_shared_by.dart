/// Why a run shared a file with Shorebird.
enum RunArtifactSharedBy {
  /// The organization's "Share debugging information with Shorebird" setting,
  /// for a failed patch run.
  setting._('setting'),

  /// The run asked with `shorebird patch --share-debug-info`.
  flag._('flag');

  const RunArtifactSharedBy._(this.value);

  /// Creates a RunArtifactSharedBy from a json value.
  factory RunArtifactSharedBy.fromJson(String json) {
    return RunArtifactSharedBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown RunArtifactSharedBy value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static RunArtifactSharedBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return RunArtifactSharedBy.fromJson(json);
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
