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
/// about `CFBundleShortVersionString` or `CFBundleVersion` (ITMS-90473). Xcode
/// normally papers over this by rewriting every embedded bundle's version at
/// export time, but that behavior is driven by
/// `manageAppVersionAndBuildNumber`, which Shorebird requires to be off so that
/// the version it records for a release is the version that actually ships.
/// The consequence is that extension versions are left as their targets built
/// them, and a mismatch surfaces as an App Store Connect rejection rather than
/// as a build failure.
///
/// An extension is skipped if its Info.plist is missing, cannot be parsed, or
/// does not declare the version keys. This is a diagnostic aid, and a
/// malformed extension plist is not something to fail or warn a release over.
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
            'but the app is "${m.appValue}"',
      )
      .join('\n');

  return '''
Your app embeds app extensions whose versions do not match the app:

$details

App Store Connect rejects uploads with mismatched extension versions
(ITMS-90473), so this will likely fail at upload time rather than now.

Shorebird builds with Xcode's "Manage Version and Build Number" disabled so
that the version recorded for this release is the version that ships, which
means Xcode will not update your extension versions for you. Set each
extension target's MARKETING_VERSION and CURRENT_PROJECT_VERSION to match the
app, or set them to \$(MARKETING_VERSION) and \$(CURRENT_PROJECT_VERSION) so
they follow it automatically.''';
}
