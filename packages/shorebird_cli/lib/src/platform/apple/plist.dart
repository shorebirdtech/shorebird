// cspell:words propertylistserialization xcarchives plutil

import 'dart:io';

import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:shorebird_cli/src/platform/apple/invalid_export_options_plist_exception.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';

/// Exception thrown when a plist file cannot be parsed.
class PlistParseException implements Exception {
  /// Creates a new [PlistParseException].
  const PlistParseException({required this.filePath, required this.cause});

  /// The path to the plist file that failed to parse.
  final String filePath;

  /// The underlying exception that caused the parse failure.
  final Exception cause;

  @override
  String toString() =>
      'Failed to parse $filePath: $cause\n'
      'Verify the plist is valid by running: plutil -lint $filePath';
}

/// A representation of an Info.plist file.
class Plist {
  /// Creates a new [Plist] from the contents of the provided [file].
  Plist({required File file}) {
    try {
      properties =
          PropertyListSerialization.propertyListWithString(
                file.readAsStringSync(),
              )
              as Map<String, Object>;
    } on PropertyListReadStreamException catch (e) {
      throw PlistParseException(filePath: file.path, cause: e);
    }
  }

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

  /// The Info.plist contained in .xcarchives has the following structure:
  /// {
  ///  ApplicationProperties: {
  ///   CFBundleShortVersionString: "1.0.0",
  ///   CFBundleVersion: "1",
  /// },
  /// This nesting is not present in Info.plist files in app bundles.
  static const applicationPropertiesKey = 'ApplicationProperties';

  /// The key in an ExportOptions.plist that, when true, instructs Xcode to
  /// rewrite CFBundleVersion in the exported IPA based on the latest build
  /// number on App Store Connect. This breaks Shorebird, because the build
  /// number that ships will not match the one Shorebird recorded for the
  /// release.
  ///
  /// See https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
  static const manageAppVersionAndBuildNumberKey =
      'manageAppVersionAndBuildNumber';

  /// The properties contained in the Info.plist file.
  late final Map<String, Object> properties;

  /// The version number of the application.
  String get versionNumber {
    final applicationProperties =
        properties.containsKey(applicationPropertiesKey)
        ? properties[applicationPropertiesKey]! as Map<String, Object>
        : properties;
    final releaseVersion = applicationProperties[releaseVersionKey] as String?;
    final buildNumber = applicationProperties[buildNumberKey] as String?;
    if (releaseVersion == null) {
      throw Exception('Could not determine release version');
    }

    return buildNumber == null
        ? releaseVersion
        : '$releaseVersion+$buildNumber';
  }

  @override
  String toString() =>
      PropertyListSerialization.stringWithPropertyList(properties);
}

/// Asserts that the user-supplied `--export-options-plist` at [file] is
/// compatible with Shorebird.
///
/// Throws [InvalidExportOptionsPlistException] if the plist sets
/// `manageAppVersionAndBuildNumber` to `true`. When that key is true, Xcode
/// rewrites `CFBundleVersion` in the exported IPA, so the build number that
/// ships to App Store Connect will not match the build number Shorebird
/// recorded for the release. Patches will then fail to match the release.
///
/// Throws [PlistParseException] if the file cannot be parsed. Returns
/// without doing anything if the file does not exist; flutter will surface
/// a clearer error when it fails to read it.
void assertValidExportOptionsPlist(File file) {
  if (!file.existsSync()) return;
  final plist = Plist(file: file);
  final value = plist.properties[Plist.manageAppVersionAndBuildNumberKey];
  if (value == true) {
    throw InvalidExportOptionsPlistException(
      '''
Exported options plist ${file.path} sets "${Plist.manageAppVersionAndBuildNumberKey}" to true.

Xcode will rewrite the build number in the exported IPA, so the version that ships to App Store Connect will not match the version Shorebird recorded for this release. Patches will fail to apply.

Set "${Plist.manageAppVersionAndBuildNumberKey}" to false (or remove the key) and try again.

See $troubleshootingUrl#patch-not-showing-up for details.''',
    );
  }
}
