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

/// Minimum Flutter version for obfuscation support across all platforms.
///
/// Obfuscation requires gen_snapshot changes (--save-obfuscation-map and
/// --strip flags) that were first available in this Flutter version.
final minimumObfuscationFlutterVersion = Version(3, 41, 2);

/// Minimum Flutter version that supports `flutter build --shorebird-trace=<path>`
/// for emitting Chrome Trace Event Format build traces.
///
/// Added in shorebirdtech/flutter#116.
final minimumBuildTraceFlutterVersion = Version(3, 41, 7);
