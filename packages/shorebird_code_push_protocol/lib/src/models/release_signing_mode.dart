/// How a release's binaries were signed for patch verification.
enum ReleaseSigningMode {
  /// The release embeds a managed key Shorebird holds in Cloud KMS, and
  /// Shorebird signs its patches.
  managed._('managed'),

  /// The release embeds a public key whose private half the customer holds,
  /// and the CLI signs its patches.
  customer._('customer'),

  /// The release embeds no key, so its patches are not verified.
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
