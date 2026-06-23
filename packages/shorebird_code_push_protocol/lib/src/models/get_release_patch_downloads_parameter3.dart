enum GetReleasePatchDownloadsParameter3 {
  patch._('patch');

  const GetReleasePatchDownloadsParameter3._(this.value);

  /// Creates a GetReleasePatchDownloadsParameter3 from a json value.
  factory GetReleasePatchDownloadsParameter3.fromJson(String json) {
    return GetReleasePatchDownloadsParameter3.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetReleasePatchDownloadsParameter3 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetReleasePatchDownloadsParameter3? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchDownloadsParameter3.fromJson(json);
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
