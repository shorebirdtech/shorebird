import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:shorebird_cli/src/command.dart';

/// Helpers to determine the release and build number of an iOS app.
mixin ShorebirdIosReleaseVersionMixin on ShorebirdCommand {
  /// This key is a user-visible string for the version of the bundle. The
  /// required format is three period-separated integers, such as 10.14.1. The
  /// string can only contain numeric characters (0-9) and periods.
  ///
  /// See https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleshortversionstring
  static const releaseVersionKey = 'CFBundleShortVersionString';

  /// The version of the build that identifies an iteration of the bundle.
  ///
  /// See https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleversion
  static const buildNumberKey = 'CFBundleVersion';

  /// Checks the iOS Info.plist and referenced .xcconfig files to determine the
  /// app's release version and build number.
  Future<String> determineIosReleaseVersion() async {
    final configPropertyRegex = RegExp(r'\$\((\w+)\)');

    // TODO(bryanoltman): is it safe to assume "Runner" as the target name?
    final plistPath = p.join(
      Directory.current.path,
      'ios',
      'Runner',
      'Info.plist',
    );

    final plist = PropertyListSerialization.propertyListWithString(
      File(plistPath).readAsStringSync(),
    ) as Map<String, Object>;
    final pListVariables = _configVariables(
      path: p.join(
        Directory.current.path,
        'ios',
        'Flutter',
        'Release.xcconfig',
      ),
    );
    var releaseVersion = plist[releaseVersionKey] as String?;
    var buildNumber = plist[buildNumberKey] as String?;

    if (releaseVersion == null) {
      throw Exception('Could not determine release version');
    }

    if (configPropertyRegex.hasMatch(releaseVersion)) {
      releaseVersion = pListVariables[
          configPropertyRegex.firstMatch(releaseVersion)!.group(1)!];
      if (releaseVersion == null) {
        throw Exception('Could not determine release version');
      }
    }

    if (buildNumber != null && configPropertyRegex.hasMatch(buildNumber)) {
      buildNumber = pListVariables[
          configPropertyRegex.firstMatch(buildNumber)!.group(1)!];
    }

    return [releaseVersion, buildNumber].whereType<String>().join('+');
  }

  /// Accepts a path to an .xcconfig file and returns a map of the variables
  /// it defines. If the file contains an `#include` directive, the included
  /// file will be recursively parsed and its variables will be included in the
  /// map.
  Map<String, String> _configVariables({required String path}) {
    final properties = <String, String>{};
    final includeRegex = RegExp(r'^#include "(.+)"$');
    final lines = File(path).readAsLinesSync();
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('//')) {
        continue;
      }

      if (includeRegex.hasMatch(line)) {
        final fileName = includeRegex.firstMatch(line)!.group(1)!;
        properties.addEntries(
          _configVariables(path: p.join(p.dirname(path), fileName)).entries,
        );
        continue;
      }

      final parts = line.split('=');
      properties[parts[0]] = parts[1];
    }

    return properties;
  }
}
