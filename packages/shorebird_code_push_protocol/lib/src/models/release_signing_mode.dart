/// How a release's binaries were signed for patch signing.
enum ReleaseSigningMode {
  /// The release embeds a key Shorebird holds, which signs every patch to it.
  managed._('managed'),

  /// The release embeds a key the customer holds, who signs every patch.
  customer._('customer'),

  /// The release embeds no key, so its patches are not signed.
  unsigned._('unsigned');

  const ReleaseSigningMode._(this.value);

  /// Creates a ReleaseSigningMode from a json value.
  factory ReleaseSigningMode.fromJson(String json) {
    return ReleaseSigningMode.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ReleaseSigningMode value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ReleaseSigningMode? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ReleaseSigningMode.fromJson(json);
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
