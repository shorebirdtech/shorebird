import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:plist_parser/plist_parser.dart';

/// {@template ipa}
/// A class that represents an iOS IPA file.
/// {@endtemplate}
class Ipa {
  /// {@macro ipa}
  Ipa({
    required String path,
  }) : _ipaFile = File(path);

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

  final File _ipaFile;

  /// The version number of the IPA, as derived from the app's Info.plist.
  String get versionNumber {
    final plist = _getPlist();
    final releaseVersion = plist[releaseVersionKey] as String;
    final buildNumber = plist[buildNumberKey] as String;
    return '$releaseVersion+$buildNumber';
  }

  Map<dynamic, dynamic> _getPlist() {
    final plistPathRegex = RegExp(r'Payload/[\w]+.app/Info.plist');
    final content = ZipDecoder()
        .decodeBuffer(InputFileStream(_ipaFile.path))
        .files
        .where((file) {
          return file.isFile && plistPathRegex.hasMatch(file.name);
        })
        .first
        .content as List<int>;

    final stringContent = String.fromCharCodes(content);
    return PlistParser().parse(stringContent);
  }
}
