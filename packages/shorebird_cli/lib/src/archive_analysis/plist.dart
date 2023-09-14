import 'dart:io';

import 'package:propertylistserialization/propertylistserialization.dart';

class Plist {
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
  static const applicationPropertiesKey = 'ApplicationProperties';

  late final Map<String, Object> properties;

  String get versionNumber {
    final Map<String, Object> effectivePlist;
    if (properties.containsKey(applicationPropertiesKey)) {
      effectivePlist =
          properties[applicationPropertiesKey]! as Map<String, Object>;
    } else {
      effectivePlist = properties;
    }

    final releaseVersion = effectivePlist[releaseVersionKey] as String?;
    final buildNumber = effectivePlist[buildNumberKey] as String?;
    if (releaseVersion == null) {
      throw Exception('Could not determine release version');
    }

    return buildNumber == null
        ? releaseVersion
        : '$releaseVersion+$buildNumber';
  }
}
