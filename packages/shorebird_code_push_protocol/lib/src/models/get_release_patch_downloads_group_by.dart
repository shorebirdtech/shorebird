enum GetReleasePatchDownloadsGroupBy {
  patch._('patch');

  const GetReleasePatchDownloadsGroupBy._(this.value);

  /// Creates a GetReleasePatchDownloadsGroupBy from a json value.
  factory GetReleasePatchDownloadsGroupBy.fromJson(String json) {
    return GetReleasePatchDownloadsGroupBy.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetReleasePatchDownloadsGroupBy value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetReleasePatchDownloadsGroupBy? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchDownloadsGroupBy.fromJson(json);
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
