/// The status of a release.
enum ReleaseStatus {
  /// Indicates that the release has been created, but not all platform
  /// artifacts have been uploaded.
  draft,

  /// Indicates that all platform artifacts have been uploaded for this release.
  active;

  /// Returns the [ReleaseStatus] with the given [name].
  factory ReleaseStatus.named(String name) =>
      ReleaseStatus.values.firstWhere((status) => status.name == name);
}
