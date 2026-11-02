enum GetUniqueUsersGranularity {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetUniqueUsersGranularity._(this.value);

  /// Creates a GetUniqueUsersGranularity from a json value.
  factory GetUniqueUsersGranularity.fromJson(String json) {
    return GetUniqueUsersGranularity.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetUniqueUsersGranularity value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetUniqueUsersGranularity? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetUniqueUsersGranularity.fromJson(json);
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
