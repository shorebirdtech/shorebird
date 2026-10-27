enum GetAppPatchInstallsGroupBy {
  release._('release');

  const GetAppPatchInstallsGroupBy._(this.value);

  /// Creates a GetAppPatchInstallsGroupBy from a json value.
  factory GetAppPatchInstallsGroupBy.fromJson(String json) {
    return GetAppPatchInstallsGroupBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchInstallsGroupBy value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchInstallsGroupBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchInstallsGroupBy.fromJson(json);
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
