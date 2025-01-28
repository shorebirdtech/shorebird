import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<String?> versionFromLinuxBundle({required Directory bundleRoot}) async {
  final jsonFile = File(
    p.join(
      bundleRoot.path,
      'data',
      'flutter_assets',
      'version.json',
    ),
  );
  if (!jsonFile.existsSync()) {
    return null;
  }

  final json = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
  final version = json['version'] as String?;
  final buildNumber = json['buildNumber'] as String?;
  if (version == null || buildNumber == null) {
    return null;
  }

  return '$version+$buildNumber';
}
