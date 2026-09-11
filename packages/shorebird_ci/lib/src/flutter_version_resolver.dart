import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_ci/src/pubspec.dart';
import 'package:yaml/yaml.dart';

/// Given a path to a Flutter package, attempts to determine the Flutter
/// version that should be used to build the package.
///
/// Checks the `environment.flutter` field in pubspec.yaml. If an exact
/// version is specified, returns it. If a version constraint is found,
/// returns `null` (constraints are not supported — callers should fall
/// back to `stable`). If no version is found, returns `null`.
String? resolveFlutterVersion({required String packagePath}) {
  final pubspec = readPubspec(packagePath);
  final environment = pubspec?['environment'] as YamlMap?;
  final flutterVersionString = environment?['flutter'] as String?;
  if (flutterVersionString == null) return null;

  final version = VersionConstraint.parse(flutterVersionString);
  if (version is Version) return version.toString();

  // It's a constraint (e.g., ">=3.19.0 <4.0.0"), not an exact version.
  return null;
}

/// Like [resolveFlutterVersion] but falls back to `'stable'` when no
/// exact version is pinned. This is what the `flutter_version` CLI
/// emits — it always produces something `subosito/flutter-action` can
/// accept.
String resolveFlutterVersionOrStable({required String packagePath}) =>
    resolveFlutterVersion(packagePath: packagePath) ?? 'stable';
