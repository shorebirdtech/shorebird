enum GetAppPatchInstallsParameter3 {
  release._('release');

  const GetAppPatchInstallsParameter3._(this.value);

  /// Creates a GetAppPatchInstallsParameter3 from a json value.
  factory GetAppPatchInstallsParameter3.fromJson(String json) {
    return GetAppPatchInstallsParameter3.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchInstallsParameter3 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchInstallsParameter3? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchInstallsParameter3.fromJson(json);
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
