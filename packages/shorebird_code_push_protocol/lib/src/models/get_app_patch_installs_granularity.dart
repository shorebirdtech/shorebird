enum GetAppPatchInstallsGranularity {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetAppPatchInstallsGranularity._(this.value);

  /// Creates a GetAppPatchInstallsGranularity from a json value.
  factory GetAppPatchInstallsGranularity.fromJson(String json) {
    return GetAppPatchInstallsGranularity.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchInstallsGranularity value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchInstallsGranularity? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchInstallsGranularity.fromJson(json);
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
