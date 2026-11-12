/// What a file a run shared is. Each kind has its own rule for when
/// the customer has agreed to share it.
enum RunArtifactKind {
  /// A patch run's `build/patch-debug.zip`. Shared when the run asked
  /// with `share_debug_info`, or when it failed and the organization's
  /// "Share debugging information with Shorebird" setting is on.
  debugBundle._('debug_bundle');

  const RunArtifactKind._(this.value);

  /// Creates a RunArtifactKind from a json value.
  factory RunArtifactKind.fromJson(String json) {
    return RunArtifactKind.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown RunArtifactKind value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static RunArtifactKind? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return RunArtifactKind.fromJson(json);
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
