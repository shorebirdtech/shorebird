enum GetOrganizationAppsParameter5 {
  updated._('updated'),
  created._('created'),
  name._('name');

  const GetOrganizationAppsParameter5._(this.value);

  /// Creates a GetOrganizationAppsParameter5 from a json value.
  factory GetOrganizationAppsParameter5.fromJson(String json) {
    return GetOrganizationAppsParameter5.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetOrganizationAppsParameter5 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetOrganizationAppsParameter5? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAppsParameter5.fromJson(json);
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
