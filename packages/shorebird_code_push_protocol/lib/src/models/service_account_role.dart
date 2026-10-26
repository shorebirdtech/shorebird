/// A role a service account can hold in its organization: a subset of
/// `Role`. Never `admin` or `owner`, so a leaked key cannot manage the
/// organization's members or its other service accounts.
enum ServiceAccountRole {
  /// Read-only access to the organization.
  viewer._('viewer'),

  /// Can manage releases and patches.
  developer._('developer'),

  /// Can manage apps, as well as releases and patches.
  appManager._('appManager'),

  /// Can read the organization's audit log and nothing else.
  auditor._('auditor');

  const ServiceAccountRole._(this.value);

  /// Creates a ServiceAccountRole from a json value.
  factory ServiceAccountRole.fromJson(String json) {
    return ServiceAccountRole.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ServiceAccountRole value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ServiceAccountRole? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ServiceAccountRole.fromJson(json);
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
