/// What the symbol file's bytes are compressed with. The server never
/// reads the bytes, so the client says which codec it used and the object
/// carries that as its content type.
enum SymbolsCompression {
  gzip._('gzip'),
  zstd._('zstd');

  const SymbolsCompression._(this.value);

  /// Creates a SymbolsCompression from a json value.
  factory SymbolsCompression.fromJson(String json) {
    return SymbolsCompression.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown SymbolsCompression value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static SymbolsCompression? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return SymbolsCompression.fromJson(json);
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
