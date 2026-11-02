/// The name of `type_id`.
enum AuditLogActorUserType {
  user._('User'),
  service._('Service'),
  shorebirdStaff._('shorebird_staff');

  const AuditLogActorUserType._(this.value);

  /// Creates a AuditLogActorUserType from a json value.
  factory AuditLogActorUserType.fromJson(String json) {
    return AuditLogActorUserType.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown AuditLogActorUserType value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static AuditLogActorUserType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return AuditLogActorUserType.fromJson(json);
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
