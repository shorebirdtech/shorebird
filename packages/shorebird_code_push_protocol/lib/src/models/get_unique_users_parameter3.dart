enum GetUniqueUsersParameter3 {
  platform._('platform');

  const GetUniqueUsersParameter3._(this.value);

  /// Creates a GetUniqueUsersParameter3 from a json value.
  factory GetUniqueUsersParameter3.fromJson(String json) {
    return GetUniqueUsersParameter3.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetUniqueUsersParameter3 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetUniqueUsersParameter3? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetUniqueUsersParameter3.fromJson(json);
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
