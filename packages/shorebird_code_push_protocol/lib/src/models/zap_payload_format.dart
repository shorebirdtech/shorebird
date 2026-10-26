/// The format of a preview build's payload.
enum ZapPayloadFormat {
  /// A zipped Flutter web build, the one format the Zap container runs.
  web1._('web-1');

  const ZapPayloadFormat._(this.value);

  /// Creates a ZapPayloadFormat from a json value.
  factory ZapPayloadFormat.fromJson(String json) {
    return ZapPayloadFormat.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ZapPayloadFormat value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ZapPayloadFormat? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ZapPayloadFormat.fromJson(json);
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
