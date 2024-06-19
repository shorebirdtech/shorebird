/// A class that holds a collection of Shorebird documentation links
/// used throughout the Shorebird CLI.
class ShorebirdDocumentation {
  /// The base URL for the Shorebird documentation.
  static const String baseUrl = 'https://docs.shorebird.dev';

  /// URL to the troubshooting section which covers the Unsupported class
  /// file major version
  static const String unsupportedClassFileVersionUrl =
      '$baseUrl/troubleshooting/#unsupported-class-file-major-version-65';

  /// URL to the documentation section which explains what makes a release
  /// not sideloadable.
  static const String nonSideloadableRelease =
      // TODO(erickzanardo): Add the real URL here.
      '$baseUrl/faq/#non-sideloadable-release';
}
