import 'dart:io';

import 'package:flutter_version_resolver/src/logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// {@template version_constraint_exception}
/// Thrown when a version constraint is found unexpectedly.
/// {@endtemplate}
class VersionConstraintException implements Exception {
  /// {@macro version_constraint_exception}
  VersionConstraintException({required this.versionConstraint});

  /// The version constraint that was found.
  final String versionConstraint;
}

/// Given a path to a Flutter package, attempts to determine the Flutter version
/// that should be used to build the package.
///
/// This checks the following locations, in this order:
///
/// 1. The `environment` section of the pubspec.yaml file
/// 2. TODO(bryanoltman): add fvm support
///
/// If no version is found, this returns the `stable` version.
String resolveFlutterVersion({
  required String packagePath,
}) {
  logger
    ..info('Resolving Flutter version for $packagePath')
    ..info('Checking pubspec.yaml environment section for flutter version');

  try {
    final flutterVersion = flutterVersionFromPubspecEnvironment(
      packagePath: packagePath,
    );
    if (flutterVersion != null) {
      logger.info('Found flutter version in pubspec.yaml: $flutterVersion');
      return flutterVersion.toString();
    }
  } on VersionConstraintException catch (e) {
    logger.err(
      '''Found version constraint: ${e.versionConstraint}. Version constraints are not supported in pubspec.yaml. Please specify a specific version.''',
    );
    return 'stable';
  } on Exception catch (e) {
    logger
      ..err('Error resolving Flutter version: $e')
      ..info('Falling back to "stable" branch');
    return 'stable';
  }

  logger.info('No flutter version found in pubspec.yaml, using stable');
  return 'stable';
}

/// Returns the Flutter version specified in the `environment` section of the
/// pubspec.yaml file, or `null` if no version is specified.
///
/// A pubspec.yaml with the following will return `Version(3, 20, 0)`:
/// ```yaml
/// environment:
///   sdk: ^3.8.1
///   flutter: 3.20.0
/// ```
Version? flutterVersionFromPubspecEnvironment({required String packagePath}) {
  final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw Exception('pubspec.yaml not found at ${pubspecFile.path}');
  }

  final pubspecYaml = loadYaml(pubspecFile.readAsStringSync());
  if (pubspecYaml is! YamlMap) {
    throw Exception('Failed to parse pubspec.yaml at ${pubspecFile.path}');
  }

  final environment = pubspecYaml['environment'] as YamlMap?;
  final flutterVersionString = environment?['flutter'] as String?;
  if (flutterVersionString == null) {
    return null;
  }

  final version = VersionConstraint.parse(flutterVersionString);
  if (version is Version) {
    return version;
  }

  // We were successfully able to parse the flutterVersionString, but it is a
  // version constraint, not a specific version.
  throw VersionConstraintException(versionConstraint: flutterVersionString);
}
