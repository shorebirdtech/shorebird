/// Distinguishes the personal organization created with each user
/// account from team organizations.
enum OrganizationType {
  /// The organization implicitly created with each user account. Its owner
  /// can invite members.
  personal._('personal'),

  /// A multi-user organization with collaborators.
  team._('team');

  const OrganizationType._(this.value);

  /// Creates a OrganizationType from a json value.
  factory OrganizationType.fromJson(String json) {
    return OrganizationType.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown OrganizationType value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static OrganizationType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return OrganizationType.fromJson(json);
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
