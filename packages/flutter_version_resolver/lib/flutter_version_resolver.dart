import 'dart:io';

import 'package:flutter_version_resolver/src/logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

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

  final flutterVersion = flutterVersionFromPubspecEnvironment(
    packagePath: packagePath,
  );
  if (flutterVersion != null) {
    logger.info('Found flutter version in pubspec.yaml: $flutterVersion');
    return flutterVersion.toString();
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

  return Version.parse(flutterVersionString);
}
