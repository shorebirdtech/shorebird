enum GetReleasePatchInstallsParameter3 {
  patch._('patch');

  const GetReleasePatchInstallsParameter3._(this.value);

  /// Creates a GetReleasePatchInstallsParameter3 from a json value.
  factory GetReleasePatchInstallsParameter3.fromJson(String json) {
    return GetReleasePatchInstallsParameter3.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetReleasePatchInstallsParameter3 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetReleasePatchInstallsParameter3? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchInstallsParameter3.fromJson(json);
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
