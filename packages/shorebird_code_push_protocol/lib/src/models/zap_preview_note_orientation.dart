/// Which way the device was held when a note was left.
enum ZapPreviewNoteOrientation {
  /// Portrait.
  portrait._('portrait'),

  /// Landscape.
  landscape._('landscape');

  const ZapPreviewNoteOrientation._(this.value);

  /// Creates a ZapPreviewNoteOrientation from a json value.
  factory ZapPreviewNoteOrientation.fromJson(String json) {
    return ZapPreviewNoteOrientation.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown ZapPreviewNoteOrientation value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ZapPreviewNoteOrientation? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewNoteOrientation.fromJson(json);
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
