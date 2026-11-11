/// What linking did for a created patch.
/// Unstable: this may change shape until patch linking ships.
enum PatchLinkResult {
  /// The patch joined a number that patches for other platforms with the same
  /// key already have.
  linked._('linked'),

  /// The server returned this platform's unfinished patch from an earlier
  /// request with the same key (`created` is false).
  reused._('reused'),

  /// Another patch has the key, but this one could not join its number (see
  /// `reason`) and took a new number.
  notLinked._('not_linked'),

  /// Nothing to link to, so the patch took a new number. The request had no
  /// key or no platform, linking is off, or no other patch on the release has
  /// the key.
  none._('none');

  const PatchLinkResult._(this.value);

  /// Creates a PatchLinkResult from a json value.
  factory PatchLinkResult.fromJson(String json) {
    return PatchLinkResult.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown PatchLinkResult value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static PatchLinkResult? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return PatchLinkResult.fromJson(json);
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
