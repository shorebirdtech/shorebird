enum GetAppPatchDownloadsGranularity {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetAppPatchDownloadsGranularity._(this.value);

  /// Creates a GetAppPatchDownloadsGranularity from a json value.
  factory GetAppPatchDownloadsGranularity.fromJson(String json) {
    return GetAppPatchDownloadsGranularity.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetAppPatchDownloadsGranularity value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetAppPatchDownloadsGranularity? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetAppPatchDownloadsGranularity.fromJson(json);
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
