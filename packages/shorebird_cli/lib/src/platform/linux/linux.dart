import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [Linux] instance.
final linuxRef = create(Linux.new);

/// The [Linux] instance available in the current zone.
Linux get linux => read(linuxRef);

/// A class that provides Linux-specific functionality.
class Linux {
  /// Linux apps track their version in a json file at
  /// data/flutter_assets/version.json.
  File linuxBundleVersionFile(Directory bundleRoot) => File(
    p.join(bundleRoot.absolute.path, 'data', 'flutter_assets', 'version.json'),
  );

  /// Reads the version from a Linux Flutter bundle.
  ///
  /// Linux executables do not have an intrinsic version number. Because of
  /// this, version info is stored in a json file at
  /// data/flutter_assets/version.json.
  String versionFromLinuxBundle({required Directory bundleRoot}) {
    final jsonFile = linuxBundleVersionFile(bundleRoot);
    if (!jsonFile.existsSync()) {
      throw Exception(
        'Version file not found in Linux bundle (expected at ${jsonFile.path})',
      );
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
}
