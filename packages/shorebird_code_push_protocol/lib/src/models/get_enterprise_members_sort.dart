enum GetEnterpriseMembersSort {
  person._('person'),
  minusPerson._('-person'),
  account._('account'),
  minusAccount._('-account'),
  role._('role'),
  minusRole._('-role'),
  lastSignIn._('last_sign_in'),
  minusLastSignIn._('-last_sign_in'),
  lastActive._('last_active'),
  minusLastActive._('-last_active'),
  removed._('removed'),
  minusRemoved._('-removed'),
  removedBy._('removed_by'),
  minusRemovedBy._('-removed_by');

  const GetEnterpriseMembersSort._(this.value);

  /// Creates a GetEnterpriseMembersSort from a json value.
  factory GetEnterpriseMembersSort.fromJson(String json) {
    return GetEnterpriseMembersSort.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetEnterpriseMembersSort value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetEnterpriseMembersSort? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseMembersSort.fromJson(json);
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
