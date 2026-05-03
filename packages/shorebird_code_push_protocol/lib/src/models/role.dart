/// A role that a user can have relative to an Organization or App.
enum Role {
  /// User that created the organization.
  owner._('owner'),

  /// Users who have permissions to manage the organization.
  admin._('admin'),

  /// Users who have permissions to manage an app.
  appManager._('appManager'),

  /// Users who are part of the organization but have limited permissions.
  developer._('developer'),

  /// Users who have read-only access to the organization.
  viewer._('viewer'),

  /// Users who are not part of the organization but have visibility into it
  /// via app collaborator permissions.
  none._('none');

  const Role._(this.value);

  /// Creates a Role from a json value.
  factory Role.fromJson(String json) {
    return Role.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException('Unknown Role value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static Role? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return Role.fromJson(json);
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
