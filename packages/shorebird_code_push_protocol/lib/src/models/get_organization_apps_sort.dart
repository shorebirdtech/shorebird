enum GetOrganizationAppsSort {
  updated._('updated'),
  created._('created'),
  name._('name');

  const GetOrganizationAppsSort._(this.value);

  /// Creates a GetOrganizationAppsSort from a json value.
  factory GetOrganizationAppsSort.fromJson(String json) {
    return GetOrganizationAppsSort.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown GetOrganizationAppsSort value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetOrganizationAppsSort? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAppsSort.fromJson(json);
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
