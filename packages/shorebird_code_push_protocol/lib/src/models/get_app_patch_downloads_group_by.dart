enum GetAppPatchDownloadsGroupBy {
  release._('release');

  const GetAppPatchDownloadsGroupBy._(this.value);

  /// Creates a GetAppPatchDownloadsGroupBy from a json value.
  factory GetAppPatchDownloadsGroupBy.fromJson(String json) {
    return GetAppPatchDownloadsGroupBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchDownloadsGroupBy value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchDownloadsGroupBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchDownloadsGroupBy.fromJson(json);
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
