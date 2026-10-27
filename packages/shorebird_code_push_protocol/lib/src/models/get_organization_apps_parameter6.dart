enum GetOrganizationAppsParameter6 {
  asc._('asc'),
  desc._('desc');

  const GetOrganizationAppsParameter6._(this.value);

  /// Creates a GetOrganizationAppsParameter6 from a json value.
  factory GetOrganizationAppsParameter6.fromJson(String json) {
    return GetOrganizationAppsParameter6.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetOrganizationAppsParameter6 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetOrganizationAppsParameter6? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAppsParameter6.fromJson(json);
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
