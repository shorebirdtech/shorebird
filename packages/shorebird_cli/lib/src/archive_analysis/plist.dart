// cspell:words propertylistserialization xcarchives

import 'dart:io';

import 'package:propertylistserialization/propertylistserialization.dart';

/// A representation of an Info.plist file.
class Plist {
  /// Creates a new [Plist] from the contents of the provided [file].
  Plist({required File file}) {
    properties = PropertyListSerialization.propertyListWithString(
      file.readAsStringSync(),
    ) as Map<String, Object>;
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
