enum GetEnterpriseGuestsSort {
  person._('person'),
  minusPerson._('-person'),
  lastSignIn._('last_sign_in'),
  minusLastSignIn._('-last_sign_in'),
  lastActive._('last_active'),
  minusLastActive._('-last_active');

  const GetEnterpriseGuestsSort._(this.value);

  /// Creates a GetEnterpriseGuestsSort from a json value.
  factory GetEnterpriseGuestsSort.fromJson(String json) {
    return GetEnterpriseGuestsSort.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown GetEnterpriseGuestsSort value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetEnterpriseGuestsSort? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseGuestsSort.fromJson(json);
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
