import 'package:pub_semver/pub_semver.dart';

/// The minimum allowed Flutter version for creating iOS releases.
///
/// This constraint exists because iOS code push support requires specific
/// Flutter engine changes that were first available in this version.
final minimumSupportedIosFlutterVersion = Version(3, 22, 2);

/// The minimum allowed Flutter version for creating macOS releases.
///
/// macOS code push support was introduced later than iOS and requires
/// Flutter engine changes that were first available in this version.
final minimumSupportedMacosFlutterVersion = Version(3, 27, 4);

/// The minimum allowed Flutter version for creating Linux releases.
///
/// Linux code push support requires Flutter engine changes that were first
/// available in this version.
final minimumSupportedLinuxFlutterVersion = Version(3, 27, 4);

/// The minimum allowed Flutter version for creating Windows releases.
///
/// Windows code push support requires Flutter engine changes that were first
/// available in this version.
final minimumSupportedWindowsFlutterVersion = Version(3, 32, 6);

/// Minimum Flutter version for module version support.
///
/// This version introduced SHOREBIRD_MODULE_VERSION env var support in the
/// Flutter tool, which allows AAR releases to embed a version identity
/// independent of the host app's version.
final minimumModuleVersionFlutterVersion = Version(3, 41, 4);

/// Minimum Flutter version for obfuscation support across all platforms.
///
/// Obfuscation requires gen_snapshot changes (--save-obfuscation-map and
/// --strip flags) that were first available in this Flutter version.
final minimumObfuscationFlutterVersion = Version(3, 41, 2);
