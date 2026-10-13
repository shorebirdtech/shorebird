import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/apple/plist.dart';

/// {@template app_extension_version_mismatch}
/// A version key whose value in an app extension does not match the value in
/// the extension's containing app.
/// {@endtemplate}
class AppExtensionVersionMismatch {
  /// {@macro app_extension_version_mismatch}
  const AppExtensionVersionMismatch({
    required this.extensionName,
    required this.key,
    required this.appValue,
    required this.extensionValue,
  });

  /// The file name of the .appex bundle, e.g. `NotificationService.appex`.
  final String extensionName;

  /// The Info.plist key that differs, either [Plist.releaseVersionKey] or
  /// [Plist.buildNumberKey].
  final String key;

  /// The value of [key] in the containing app's Info.plist.
  final String appValue;

  /// The value of [key] in the extension's Info.plist.
  final String extensionValue;
}

/// Returns the version mismatches between the app bundle at [appDirectory] and
/// the app extensions it embeds.
///
/// Apple rejects uploads whose extensions disagree with their containing app
/// about `CFBundleShortVersionString` or `CFBundleVersion` (ITMS-90473).
///
/// Xcode rewrites embedded bundle versions at export time when
/// `manageAppVersionAndBuildNumber` is set. Shorebird requires it off so the
/// version it records for a release is the version that ships, so extension
/// versions stay as their targets built them and a mismatch surfaces as an App
/// Store Connect rejection.
///
/// An extension is skipped if its Info.plist is missing, cannot be parsed, or
/// does not declare the version keys.
List<AppExtensionVersionMismatch> findAppExtensionVersionMismatches({
  required Directory appDirectory,
}) {
  final appPlistFile = File(p.join(appDirectory.path, 'Info.plist'));
  if (!appPlistFile.existsSync()) return [];

  final Plist appPlist;
  try {
    appPlist = Plist(file: appPlistFile);
  } on Exception {
    return [];
  }

  final pluginsDirectory = Directory(p.join(appDirectory.path, 'PlugIns'));
  if (!pluginsDirectory.existsSync()) return [];

  final mismatches = <AppExtensionVersionMismatch>[];
  final extensionDirectories =
      pluginsDirectory
          .listSync()
          .whereType<Directory>()
          .where((d) => p.extension(d.path) == '.appex')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final extensionDirectory in extensionDirectories) {
    final extensionPlistFile = File(
      p.join(extensionDirectory.path, 'Info.plist'),
    );
    if (!extensionPlistFile.existsSync()) continue;

    final Plist extensionPlist;
    try {
      extensionPlist = Plist(file: extensionPlistFile);
    } on Exception {
      continue;
    }

    for (final key in [Plist.releaseVersionKey, Plist.buildNumberKey]) {
      final appValue = appPlist.properties[key];
      final extensionValue = extensionPlist.properties[key];
      if (appValue is! String || extensionValue is! String) continue;
      if (appValue == extensionValue) continue;

      mismatches.add(
        AppExtensionVersionMismatch(
          extensionName: p.basename(extensionDirectory.path),
          key: key,
          appValue: appValue,
          extensionValue: extensionValue,
        ),
      );
    }
  }

  return mismatches;
}

/// The warning shown when [findAppExtensionVersionMismatches] finds a
/// mismatch.
String appExtensionVersionMismatchWarning(
  List<AppExtensionVersionMismatch> mismatches,
) {
  final details = mismatches
      .map(
        (m) =>
            '  ${m.extensionName}: ${m.key} is "${m.extensionValue}", '
            'the app is "${m.appValue}"',
      )
      .join('\n');

  return '''
These app extensions have versions that do not match the app:

$details

App Store Connect rejects uploads with mismatched extension versions
(ITMS-90473).

Shorebird builds with Xcode's "Manage Version and Build Number" disabled, so
Xcode does not update extension versions for you. Set each extension target's
MARKETING_VERSION and CURRENT_PROJECT_VERSION to match the app, or to
\$(MARKETING_VERSION) and \$(CURRENT_PROJECT_VERSION).''';
}
