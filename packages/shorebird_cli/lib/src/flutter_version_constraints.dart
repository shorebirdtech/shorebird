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

/// A Flutter support rule that combines a minimum version floor with an
/// allowlist of specific Shorebird-fork engine revisions below the floor
/// that also satisfy the rule.
///
/// Shorebird ships its own Flutter fork, and a single upstream Flutter
/// version can back multiple Shorebird-fork engine revisions. When a
/// feature first lands in a Shorebird-fork revision of version N before
/// upstream produces N+1, a pure min-version gate of N+1 would reject
/// users on those perfectly-good N revisions. The allowlist is a bridge
/// for exactly that window: list the engine revisions of version N that
/// include the feature, and once upstream produces N+1 the allowlist
/// stops mattering.
///
/// Append a hash to [allowedRevisions] every time Shorebird re-ships the
/// pre-floor Flutter version with the feature still included.
class FlutterSupportConstraint {
  /// Creates a constraint with the given [minVersion] floor and optional
  /// [allowedRevisions] bridge.
  const FlutterSupportConstraint({
    required this.minVersion,
    this.allowedRevisions = const {},
  });

  /// Minimum Flutter version that satisfies this constraint.
  final Version minVersion;

  /// Shorebird-fork engine revisions below [minVersion] that also satisfy
  /// this constraint.
  final Set<String> allowedRevisions;

  /// Whether the given [version]/[revision] pair satisfies this constraint.
  bool isSatisfiedBy({required Version version, required String revision}) =>
      version >= minVersion || allowedRevisions.contains(revision);
}

/// Flutter support for `flutter build --shorebird-trace=<path>` for emitting
/// Chrome Trace Event Format build traces.
///
/// Added in shorebirdtech/flutter#116. `minVersion` is set to the next
/// minor past the latest Shorebird Flutter release (currently 3.41.6), so
/// whenever that PR gets cut as 3.41.7 the floor covers it cleanly. Until
/// then, the allowlist covers the current pin hash so users on it get
/// tracing today.
final buildTraceSupportConstraint = FlutterSupportConstraint(
  minVersion: Version(3, 41, 7),
  allowedRevisions: {
    // Current Shorebird Flutter pin (bin/internal/flutter.version). Can
    // be removed once a flutter_release/3.41.7 branch ships with this
    // (or a later tracing-enabled) commit at its tip.
    '3b10eecea184bb381f1045a878eeff36548ed11e',
  },
);
