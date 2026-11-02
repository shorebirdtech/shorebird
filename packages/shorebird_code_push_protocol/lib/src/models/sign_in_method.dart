/// How a person signs in, named from their identity's issuer.
enum SignInMethod {
  google._('google'),
  microsoft._('microsoft'),
  saml._('saml'),
  other._('other');

  const SignInMethod._(this.value);

  /// Creates a SignInMethod from a json value.
  factory SignInMethod.fromJson(String json) {
    return SignInMethod.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException('Unknown SignInMethod value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static SignInMethod? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return SignInMethod.fromJson(json);
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
