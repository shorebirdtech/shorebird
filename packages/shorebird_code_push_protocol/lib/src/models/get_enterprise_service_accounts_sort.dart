enum GetEnterpriseServiceAccountsSort {
  account._('account'),
  minusAccount._('-account'),
  organization._('organization'),
  minusOrganization._('-organization'),
  createdBy._('created_by'),
  minusCreatedBy._('-created_by'),
  lastUsed._('last_used'),
  minusLastUsed._('-last_used');

  const GetEnterpriseServiceAccountsSort._(this.value);

  /// Creates a GetEnterpriseServiceAccountsSort from a json value.
  factory GetEnterpriseServiceAccountsSort.fromJson(String json) {
    return GetEnterpriseServiceAccountsSort.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetEnterpriseServiceAccountsSort value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetEnterpriseServiceAccountsSort? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseServiceAccountsSort.fromJson(json);
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
