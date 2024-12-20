/// A platform to which a Shorebird release can be deployed.
enum ReleasePlatform {
  /// Android
  android('Android'),

  /// macOS
  macos('macOS'),

  /// iOS
  ios('iOS'),

  /// Windows
  windows('Windows');

  const ReleasePlatform(this.displayName);

  /// The display name of the platform.
  final String displayName;
}
