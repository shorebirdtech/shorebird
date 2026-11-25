/// Which symbol file an upload carries. `sbsymbols` is Shorebird's own
/// SBSY v1 table, stored as `app.sbsymbols`. It is the only table
/// symbolication can read, so it is the only one an upload may carry.
enum SymbolsFormat {
  sbsymbols._('sbsymbols');

  const SymbolsFormat._(this.value);

  /// Creates a SymbolsFormat from a json value.
  factory SymbolsFormat.fromJson(String json) {
    return SymbolsFormat.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException('Unknown SymbolsFormat value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static SymbolsFormat? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return SymbolsFormat.fromJson(json);
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
