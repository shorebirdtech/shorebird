/// Whether an invitation is to an organization or to an app.
enum InvitationTargetType {
  /// The invitation grants membership in an organization.
  organization._('organization'),

  /// The invitation grants collaborator access to one app.
  app._('app');

  const InvitationTargetType._(this.value);

  /// Creates a InvitationTargetType from a json value.
  factory InvitationTargetType.fromJson(String json) {
    return InvitationTargetType.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown InvitationTargetType value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static InvitationTargetType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return InvitationTargetType.fromJson(json);
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
