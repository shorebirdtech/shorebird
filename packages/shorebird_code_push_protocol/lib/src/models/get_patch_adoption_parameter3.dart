enum GetPatchAdoptionParameter3 {
  hour._('hour'),
  day._('day'),
  week._('week'),
  month._('month');

  const GetPatchAdoptionParameter3._(this.value);

  /// Creates a GetPatchAdoptionParameter3 from a json value.
  factory GetPatchAdoptionParameter3.fromJson(String json) {
    return GetPatchAdoptionParameter3.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown GetPatchAdoptionParameter3 value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static GetPatchAdoptionParameter3? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return GetPatchAdoptionParameter3.fromJson(json);
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
