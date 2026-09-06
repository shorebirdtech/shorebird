/// The permission preset an API key is minted with.
///
/// This enum is hand-written rather than generated: API keys are minted by
/// the auth service, which is not covered by the CodePush OpenAPI spec. It
/// lives here rather than in a client because the vocabulary spans both
/// sides — the auth service mints a key against one of these presets, and
/// the CodePush server is what enforces the resulting permissions on every
/// request the key makes.
///
/// Arbitrary permission combinations are deliberately not offered. A key is
/// one of these shapes so that what it can do is legible from its scope
/// alone, without expanding a permission list to find out.
enum ApiKeyScope {
  /// Everything the minting user can do, in every organization they belong to.
  fullAccess('full_access'),

  /// Create and publish releases and patches, and read insights. No deletes,
  /// no member management, no billing.
  releaseAndPatch('release_and_patch');

  const ApiKeyScope(this.wireName);

  /// The value the auth service uses for this scope, on the wire and in the
  /// `permissions` presets it expands to.
  final String wireName;

  /// The scope whose [wireName] is [value], or null if none matches.
  ///
  /// Returns null rather than throwing for an unrecognized value: a preset
  /// added server-side is something an older client should report as unknown,
  /// not crash on and not guess at.
  static ApiKeyScope? fromWireName(String value) {
    for (final scope in ApiKeyScope.values) {
      if (scope.wireName == value) return scope;
    }
    return null;
  }
}
