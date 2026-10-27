enum GetPatchAdoptionGranularity {
  hour._('hour'),
  day._('day'),
  week._('week');

  const GetPatchAdoptionGranularity._(this.value);

  /// Creates a GetPatchAdoptionGranularity from a json value.
  factory GetPatchAdoptionGranularity.fromJson(String json) {
    return GetPatchAdoptionGranularity.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetPatchAdoptionGranularity value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetPatchAdoptionGranularity? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetPatchAdoptionGranularity.fromJson(json);
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
