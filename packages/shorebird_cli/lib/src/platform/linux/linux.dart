import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// The primary release artifact architecture for Linux releases.
/// This is a zipped copy of `build/linux/x64/release/bundle`, which is
/// produced by the `flutter build linux --release` command. It contains, at
/// its top level:
///   - data/, which contains flutter assets
///   - lib/, which contains libapp.so and libflutter_linux_gtk.so
///   - executable_flutter_app
const primaryLinuxReleaseArtifactArch = 'bundle';

/// The minimum allowed Flutter version for creating Linux releases.
final minimumSupportedLinuxFlutterVersion = Version(3, 27, 4);

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
