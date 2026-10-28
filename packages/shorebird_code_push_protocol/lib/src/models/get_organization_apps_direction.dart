enum GetOrganizationAppsDirection {
  asc._('asc'),
  desc._('desc');

  const GetOrganizationAppsDirection._(this.value);

  /// Creates a GetOrganizationAppsDirection from a json value.
  factory GetOrganizationAppsDirection.fromJson(String json) {
    return GetOrganizationAppsDirection.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetOrganizationAppsDirection value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetOrganizationAppsDirection? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAppsDirection.fromJson(json);
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
