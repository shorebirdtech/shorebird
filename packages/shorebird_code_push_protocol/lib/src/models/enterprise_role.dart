/// A person's role in an enterprise.
enum EnterpriseRole {
  /// Does everything an admin does, and also grants enterprise roles,
  /// requires a domain's sign-in method and sees billing.
  owner._('owner'),

  /// Manages the enterprise's people and policies. Does not see billing.
  admin._('admin'),

  /// Belongs to the enterprise, which by itself grants no app access.
  member._('member'),

  /// Sees the enterprise's billing and nothing else on it, and no app access.
  billingManager._('billingManager');

  const EnterpriseRole._(this.value);

  /// Creates a EnterpriseRole from a json value.
  factory EnterpriseRole.fromJson(String json) {
    return EnterpriseRole.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown EnterpriseRole value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static EnterpriseRole? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseRole.fromJson(json);
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
