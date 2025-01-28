import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads the version from a Linux Flutter bundle.
///
/// Linux executables do not have an intrinsic version number. Because of this,
/// version info is stored in a json file at data/flutter_assets/version.json.
Future<String?> versionFromLinuxBundle({required Directory bundleRoot}) async {
  final jsonFile = File(
    p.join(
      bundleRoot.absolute.path,
      'data',
      'flutter_assets',
      'version.json',
    ),
  );
  if (!jsonFile.existsSync()) {
    return null;
  }

  return _versionFromVersionJson(jsonFile);
}

String _versionFromVersionJson(File versionJsonFile) {
  final json =
      jsonDecode(versionJsonFile.readAsStringSync()) as Map<String, dynamic>;
  final version = json['version'] as String;
  final buildNumber = json['build_number'] as String;

  return '$version+$buildNumber';
}
