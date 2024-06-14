/// A platform to which a Shorebird release can be deployed.
enum ReleasePlatform {
  // ignore: public_member_api_docs
  android('Android', 'aab'),
  // ignore: public_member_api_docs
  ios('iOS', 'app');

  const ReleasePlatform(this.displayName, this.extension);

  /// The display name of the platform.
  final String displayName;

  /// The file extension for the platform.
  final String extension;
}
