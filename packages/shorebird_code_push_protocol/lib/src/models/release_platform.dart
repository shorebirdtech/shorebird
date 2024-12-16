/// A platform to which a Shorebird release can be deployed.
enum ReleasePlatform {
  // ignore: public_member_api_docs
  android('Android'),
  // ignore: public_member_api_docs
  macos('macOS'),
  // ignore: public_member_api_docs
  ios('iOS'),
  // ignore: public_member_api_docs
  windows('Windows');

  const ReleasePlatform(this.displayName);

  /// The display name of the platform.
  final String displayName;
}
