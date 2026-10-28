enum GetReleasePatchInstallsGroupBy {
  patch._('patch');

  const GetReleasePatchInstallsGroupBy._(this.value);

  /// Creates a GetReleasePatchInstallsGroupBy from a json value.
  factory GetReleasePatchInstallsGroupBy.fromJson(String json) {
    return GetReleasePatchInstallsGroupBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetReleasePatchInstallsGroupBy value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetReleasePatchInstallsGroupBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchInstallsGroupBy.fromJson(json);
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
