/// Distinguishes personal organizations (single-user) from team
/// organizations (multi-user).
enum OrganizationType {
  /// A single-user organization implicitly created with each user account.
  personal._('personal'),

  /// A multi-user organization with collaborators.
  team._('team');

  const OrganizationType._(this.value);

  /// Creates a OrganizationType from a json string.
  factory OrganizationType.fromJson(String json) {
    return OrganizationType.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown OrganizationType value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static OrganizationType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return OrganizationType.fromJson(json);
  }

  /// The value of the enum, as a string.  This is the exact value
  /// from the OpenAPI spec and will be used for network transport.
  final String value;

  /// Converts the enum to a json string.
  String toJson() => value;

  /// Returns the string value of the enum.
  @override
  String toString() => value;
}
