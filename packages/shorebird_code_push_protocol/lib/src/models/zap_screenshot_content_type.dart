/// The content type of a note's screenshot.
enum ZapScreenshotContentType {
  /// PNG.
  imagePng._('image/png'),

  /// JPEG.
  imageJpeg._('image/jpeg');

  const ZapScreenshotContentType._(this.value);

  /// Creates a ZapScreenshotContentType from a json value.
  factory ZapScreenshotContentType.fromJson(String json) {
    return ZapScreenshotContentType.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown ZapScreenshotContentType value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ZapScreenshotContentType? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ZapScreenshotContentType.fromJson(json);
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
