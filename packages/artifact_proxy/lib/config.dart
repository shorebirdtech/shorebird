import 'dart:io';

/// These are the URL patterns for all known artifact paths that Flutter
/// downloads. If there is a Shorebird-specific override for an artifact, it
/// will be downloaded from the shorebird servers. Otherwise, the standard
/// Flutter version will be downloaded.
///
/// Patterns which contain an engine revision.
final engineArtifactPatterns = {
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64\/windows-x64-flutter\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64\/font-subset.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64\/flutter-cpp-client-wrapper\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64-release\/windows-x64-flutter\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64-profile\/windows-x64-flutter\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/windows-x64-debug\/windows-x64-flutter\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/sky_engine\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64\/linux-x64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64\/font-subset\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64-release\/linux-x64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64-profile\/linux-x64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-x64-debug\/linux-x64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-arm64\/linux-arm64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-arm64\/font-subset\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-arm64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-arm64-release\/linux-arm64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/linux-arm64-profile\/linux-arm64-flutter-gtk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/ios\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/ios-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/ios-release\/Flutter.dSYM\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/ios-profile\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/flutter-web-sdk\.zip', // Web SDK seems to be all-platform after 3.10.0.
  r'flutter_infra_release\/flutter\/(.*)\/flutter-web-sdk-windows-x64\.zip', // Platform-specific web-sdks may no longer needed as of 3.10.0?
  r'flutter_infra_release\/flutter\/(.*)\/flutter-web-sdk-linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/flutter-web-sdk-darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/flutter_patched_sdk\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/flutter_patched_sdk_product\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64\/framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64\/gen_snapshot\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64\/font-subset\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64\/FlutterMacOS.framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-release\/FlutterMacOS.framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-profile\/FlutterMacOS.framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-profile\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-profile\/framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-profile\/gen_snapshot\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-release\/framework\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-x64-release\/gen_snapshot\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-arm64\/font-subset\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/darwin-arm64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/dart-sdk-windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/dart-sdk-linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/dart-sdk-linux-arm64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/dart-sdk-darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/dart-sdk-darwin-arm64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/engine_stamp\.json',
  r'flutter_infra_release\/flutter\/(.*)\/android-x86\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x86-jit-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-release\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-release\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-release\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-release\/symbols\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-profile\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-profile\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-profile\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-x64-profile\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-release\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-release\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-release\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-release\/symbols\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-profile\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-profile\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-profile\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-profile\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm64-profile\/symbols\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-release\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-release\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-release\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-release\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-release\/symbols\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-profile\/windows-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-profile\/linux-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-profile\/darwin-x64\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-profile\/artifacts\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/android-arm-profile\/symbols\.zip',
  r'flutter_infra_release\/flutter\/(.*)\/flutter_gpu\.zip',
  r'download.flutter.io\/io\/flutter\/x86_debug\/1\.0\.0-(.*)\/x86_debug-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/x86_64_release\/1\.0\.0-(.*)\/x86_64_release-1\.0\.0-(.*)\.pom\.sha1',
  r'download.flutter.io\/io\/flutter\/x86_64_release\/1\.0\.0-(.*)\/x86_64_release-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/x86_64_release\/1\.0\.0-(.*)\/x86_64_release-1\.0\.0-(.*)\.jar\.sha1',
  r'download.flutter.io\/io\/flutter\/x86_64_release\/1\.0\.0-(.*)\/x86_64_release-1\.0\.0-(.*)\.jar',
  r'download.flutter.io\/io\/flutter\/x86_64_release/\1\.0\.0-(.*)\/x86_64_release-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/x86_64_profile\/1\.0\.0-(.*)\/x86_64_profile-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/x86_64_debug\/1\.0\.0-(.*)\/x86_64_debug-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_release\/1\.0\.0-(.*)\/flutter_embedding_release-1\.0\.0-(.*)\.pom\.sha1',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_release\/1\.0\.0-(.*)\/flutter_embedding_release-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_release\/1\.0\.0-(.*)\/flutter_embedding_release-1\.0\.0-(.*)\.jar\.sha1',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_release\/1\.0\.0-(.*)\/flutter_embedding_release-1\.0\.0-(.*)\.jar',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_profile\/1\.0\.0-(.*)\/flutter_embedding_profile-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/flutter_embedding_debug\/1\.0\.0-(.*)\/flutter_embedding_debug-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_release\/1\.0\.0-(.*)\/armeabi_v7a_release-1\.0\.0-(.*)\.pom\.sha1',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_release\/1\.0\.0-(.*)\/armeabi_v7a_release-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_release\/1\.0\.0-(.*)\/armeabi_v7a_release-1\.0\.0-(.*)\.jar\.sha1',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_release\/1\.0\.0-(.*)\/armeabi_v7a_release-1\.0\.0-(.*)\.jar',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_profile\/1\.0\.0-(.*)\/armeabi_v7a_profile-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/armeabi_v7a_debug\/1\.0\.0-(.*)\/armeabi_v7a_debug-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_release\/1\.0\.0-(.*)\/arm64_v8a_release-1\.0\.0-(.*)\.pom\.sha1',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_release\/1\.0\.0-(.*)\/arm64_v8a_release-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_release\/1\.0\.0-(.*)\/arm64_v8a_release-1\.0\.0-(.*)\.jar\.sha1',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_release\/1\.0\.0-(.*)\/arm64_v8a_release-1\.0\.0-(.*)\.jar',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_profile\/1\.0\.0-(.*)\/arm64_v8a_profile-1\.0\.0-(.*)\.pom',
  r'download.flutter.io\/io\/flutter\/arm64_v8a_debug\/1\.0\.0-(.*)\/arm64_v8a_debug-1\.0\.0-(.*)\.pom',
};

/// Patterns for Flutter artifacts which don't depend on an engine revision.
final flutterArtifactPatterns = {
  r'flutter_infra_release\/ios-usb-dependencies\/usbmuxd\/(.*)\/usbmuxd\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/libusbmuxd\/(.*)\/libusbmuxd\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/openssl\/(.*)\/openssl\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/libplist\/(.*)\/libplist\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/libimobiledevice\/(.*)\/libimobiledevice\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/libimobiledeviceglue\/(.*)\/libimobiledeviceglue\.zip',
  r'flutter_infra_release\/ios-usb-dependencies\/ios-deploy\/(.*)\/ios-deploy\.zip',
  r'flutter_infra_release\/gradle-wrapper\/(.*)\/gradle-wrapper\.tgz',
  r'flutter_infra_release\/flutter\/fonts\/(.*)\/fonts\.zip',
  r'flutter_infra_release\/cipd\/flutter\/web\/canvaskit_bundle\/\+\/(.*)',
};

// =============================================================================
// Self-Hosted Configuration
// =============================================================================

/// Configuration for self-hosted artifact proxy.
///
/// These settings can be customized via environment variables to point to
/// your own storage infrastructure instead of Google Cloud Storage.
///
/// Environment variables:
/// - `ARTIFACT_MANIFEST_BASE_URL`: Base URL for artifact manifest files
/// - `FLUTTER_STORAGE_BASE_URL`: Base URL for standard Flutter artifacts
/// - `SHOREBIRD_STORAGE_BASE_URL`: Base URL for Shorebird-specific artifacts
class ArtifactProxyConfig {
  /// Creates a new [ArtifactProxyConfig] with the specified URLs.
  const ArtifactProxyConfig({
    this.manifestBaseUrl =
        'https://storage.googleapis.com/download.shorebird.dev',
    this.flutterStorageBaseUrl = 'https://storage.googleapis.com',
    this.shorebirdStorageBaseUrl = 'https://storage.googleapis.com',
  });

  /// Creates a new [ArtifactProxyConfig] from environment variables.
  ///
  /// If environment variables are not set, defaults to Google Cloud Storage URLs.
  factory ArtifactProxyConfig.fromEnvironment() {
    return ArtifactProxyConfig(
      manifestBaseUrl:
          Platform.environment['ARTIFACT_MANIFEST_BASE_URL'] ??
          'https://storage.googleapis.com/download.shorebird.dev',
      flutterStorageBaseUrl:
          Platform.environment['FLUTTER_STORAGE_BASE_URL'] ??
          'https://storage.googleapis.com',
      shorebirdStorageBaseUrl:
          Platform.environment['SHOREBIRD_STORAGE_BASE_URL'] ??
          'https://storage.googleapis.com',
    );
  }

  /// Base URL for fetching artifact manifest files.
  ///
  /// The manifest files describe which artifacts should be overridden
  /// with Shorebird-specific versions.
  final String manifestBaseUrl;

  /// Base URL for standard Flutter artifacts.
  ///
  /// These are the original Flutter SDK artifacts that don't require
  /// Shorebird modifications.
  final String flutterStorageBaseUrl;

  /// Base URL for Shorebird-specific artifacts.
  ///
  /// These artifacts have been modified to support code push functionality.
  final String shorebirdStorageBaseUrl;

  /// Gets the full manifest URL for a specific engine revision.
  String getManifestUrl(String revision) {
    return '$manifestBaseUrl/shorebird/$revision/artifacts_manifest.yaml';
  }
}
