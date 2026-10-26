/// Whether a note is still open.
enum ZapPreviewNoteStatus {
  /// Not yet dealt with.
  open._('open'),

  /// Acted on.
  resolved._('resolved'),

  /// Decided against.
  closed._('closed');

  const ZapPreviewNoteStatus._(this.value);

  /// Creates a ZapPreviewNoteStatus from a json value.
  factory ZapPreviewNoteStatus.fromJson(String json) {
    return ZapPreviewNoteStatus.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ZapPreviewNoteStatus value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ZapPreviewNoteStatus? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewNoteStatus.fromJson(json);
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
