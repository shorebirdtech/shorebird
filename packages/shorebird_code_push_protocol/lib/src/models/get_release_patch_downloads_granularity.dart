enum GetReleasePatchDownloadsGranularity {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetReleasePatchDownloadsGranularity._(this.value);

  /// Creates a GetReleasePatchDownloadsGranularity from a json value.
  factory GetReleasePatchDownloadsGranularity.fromJson(String json) {
    return GetReleasePatchDownloadsGranularity.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetReleasePatchDownloadsGranularity value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetReleasePatchDownloadsGranularity? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchDownloadsGranularity.fromJson(json);
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
