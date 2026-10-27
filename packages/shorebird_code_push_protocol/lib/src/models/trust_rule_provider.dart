/// The identity provider whose tokens an OIDC trust rule accepts.
enum TrustRuleProvider {
  /// GitHub Actions OIDC tokens.
  github._('github');

  const TrustRuleProvider._(this.value);

  /// Creates a TrustRuleProvider from a json value.
  factory TrustRuleProvider.fromJson(String json) {
    return TrustRuleProvider.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown TrustRuleProvider value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static TrustRuleProvider? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return TrustRuleProvider.fromJson(json);
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
