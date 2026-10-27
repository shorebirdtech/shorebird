enum GetUniqueUsersGroupBy {
  platform._('platform'),
  releaseVersion._('release_version');

  const GetUniqueUsersGroupBy._(this.value);

  /// Creates a GetUniqueUsersGroupBy from a json value.
  factory GetUniqueUsersGroupBy.fromJson(String json) {
    return GetUniqueUsersGroupBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown GetUniqueUsersGroupBy value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetUniqueUsersGroupBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetUniqueUsersGroupBy.fromJson(json);
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
