/// A platform to which a Shorebird release can be deployed.
enum ReleasePlatform {
  /// Android
  android('Android'),

  /// iOS
  ios('iOS'),

  /// Linux
  linux('Linux'),

  /// macOS
  macos('macOS'),

  /// Windows
  windows('Windows');

  const ReleasePlatform(this.displayName);

  /// The display name of the platform.
  final String displayName;

  /// Whether the platform supports flavors.
  bool get supportsFlavors => {
    ReleasePlatform.android,
    ReleasePlatform.ios,
    ReleasePlatform.macos,
  }.contains(this);
}
