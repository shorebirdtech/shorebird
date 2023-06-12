import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';

class XcarchiveReader {
  Xcarchive xcarchiveFromProjectRoot(String projectRoot) {
    final workspaceRoot = p.join(projectRoot, 'ios');
    final workspace = Directory(workspaceRoot)
        .listSync()
        .whereType<Directory>()
        .firstWhereOrNull((d) => d.path.endsWith('.xcworkspace'));
    if (workspace == null) {
      throw Exception('No .xcworkspace file found in $workspaceRoot');
    }

    final xcodeWorkspaceName = p.basename(workspace.path);
    final archiveName =
        xcodeWorkspaceName.replaceAll('.xcworkspace', '.xcarchive');
    final archivePath = p.join(
      Directory.current.path,
      'build',
      'ios',
      'archive',
      archiveName,
    );
    if (!Directory(archivePath).existsSync()) {
      throw Exception('No .xcarchive file found at $archivePath');
    }

    return Xcarchive(path: archivePath);
  }
}

class Xcarchive {
  Xcarchive({required String path}) : _file = File(path);

  final File _file;

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

  /// The key for the application properties dictionary. This wraps the
  /// properties defined in the app's Info.plist.
  static const applicationPropertiesKey = 'ApplicationProperties';

  String get versionNumber {
    final plistFile = File(p.join(_file.path, 'Info.plist'));
    final plist = PropertyListSerialization.propertyListWithString(
      plistFile.readAsStringSync(),
    ) as Map<String, Object>;
    final applicationProperties =
        plist[applicationPropertiesKey]! as Map<String, Object>;
    final releaseVersion = applicationProperties[releaseVersionKey] as String?;
    final buildNumber = applicationProperties[buildNumberKey] as String?;
    if (releaseVersion == null) {
      throw Exception('Could not determine release version');
    }

    return buildNumber == null
        ? releaseVersion
        : '$releaseVersion+$buildNumber';
  }
}
