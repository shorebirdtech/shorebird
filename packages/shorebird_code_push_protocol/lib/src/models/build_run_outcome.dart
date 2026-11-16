/// How a build run ended.
enum BuildRunOutcome {
  /// The run finished, or a dry run found no issues.
  succeeded._('succeeded'),

  /// The run stopped without publishing.
  failed._('failed');

  const BuildRunOutcome._(this.value);

  /// Creates a BuildRunOutcome from a json value.
  factory BuildRunOutcome.fromJson(String json) {
    return BuildRunOutcome.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown BuildRunOutcome value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static BuildRunOutcome? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return BuildRunOutcome.fromJson(json);
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
