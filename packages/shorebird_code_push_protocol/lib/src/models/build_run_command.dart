/// The CLI command a build run recorded.
enum BuildRunCommand {
  /// shorebird release.
  release._('release'),

  /// shorebird patch.
  patch._('patch');

  const BuildRunCommand._(this.value);

  /// Creates a BuildRunCommand from a json value.
  factory BuildRunCommand.fromJson(String json) {
    return BuildRunCommand.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown BuildRunCommand value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static BuildRunCommand? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return BuildRunCommand.fromJson(json);
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
