enum GetAppPatchDownloadsParameter2 {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetAppPatchDownloadsParameter2._(this.value);

  /// Creates a GetAppPatchDownloadsParameter2 from a json value.
  factory GetAppPatchDownloadsParameter2.fromJson(String json) {
    return GetAppPatchDownloadsParameter2.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchDownloadsParameter2 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchDownloadsParameter2? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchDownloadsParameter2.fromJson(json);
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
