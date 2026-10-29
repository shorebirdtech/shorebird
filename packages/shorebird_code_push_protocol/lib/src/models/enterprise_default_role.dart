/// A role a default organization joins people at.
enum EnterpriseDefaultRole {
  viewer._('viewer'),
  developer._('developer');

  const EnterpriseDefaultRole._(this.value);

  /// Creates a EnterpriseDefaultRole from a json value.
  factory EnterpriseDefaultRole.fromJson(String json) {
    return EnterpriseDefaultRole.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown EnterpriseDefaultRole value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static EnterpriseDefaultRole? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseDefaultRole.fromJson(json);
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
