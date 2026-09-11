enum GetAppPatchInstallsParameter2 {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetAppPatchInstallsParameter2._(this.value);

  /// Creates a GetAppPatchInstallsParameter2 from a json value.
  factory GetAppPatchInstallsParameter2.fromJson(String json) {
    return GetAppPatchInstallsParameter2.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchInstallsParameter2 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchInstallsParameter2? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchInstallsParameter2.fromJson(json);
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
