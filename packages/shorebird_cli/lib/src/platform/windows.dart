import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// The primary release artifact architecture for Windows releases.
/// This is a zipped copy of `build/windows/x64/runner/Release`, which is
/// produced by the `flutter build windows --release` command. It contains, at
/// its top level:
///   - flutter.dll
///   - app.exe (where `app` is the name of the Flutter app)
///   - data/, which contains flutter assets and the app.so file
const primaryWindowsReleaseArtifactArch = 'win_archive';

/// The minimum allowed Flutter version for creating Windows releases.
final minimumSupportedWindowsFlutterVersion = Version(3, 32, 6);

/// A reference to a [Windows] instance.
final windowsRef = create(Windows.new);

/// The [Windows] instance available in the current zone.
Windows get windows => read(windowsRef);

/// A class that provides Windows-specific functionality.
class Windows {
  /// Returns the selected application `.exe` from [releaseDir].
  ///
  /// Selection order when [projectName] is provided:
  /// 1) exact match on `<projectName>.exe`
  /// 2) first basename containing `<projectName>`
  /// 3) first `.exe`
  ///
  /// When [projectName] is null, returns the first `.exe`.
  /// Only top-level files in [releaseDir] are considered (non-recursive).
  File windowsAppExe(Directory releaseDir, {String? projectName}) {
    final exes = releaseDir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.exe')
        .toList();
    if (exes.isEmpty) {
      throw Exception('No .exe found in release artifact');
    }

    if (projectName == null) {
      return exes.first;
    }

    final exactMatch = exes.firstWhereOrNull(
      (f) => _pathMatchesName(f.path, projectName),
    );

    if (exactMatch != null) {
      return exactMatch;
    }

    final fuzzyMatch = exes.firstWhereOrNull(
      (f) => p.basename(f.path).contains(projectName),
    );

    if (fuzzyMatch != null) {
      return fuzzyMatch;
    }

    return exes.first;
  }

  /// Returns true if the basename of [path] is exactly `<projectName>.exe`.
  bool _pathMatchesName(String path, String projectName) =>
      p.basename(path) == '$projectName.exe';
}
