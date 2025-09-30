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
  /// Returns the selected application `.exe` from [releaseDirectory].
  /// Searches for an exact match for [projectName] and if none is found,
  /// falls back to returning the most recently modified executable.
  File findExecutable({
    required Directory releaseDirectory,
    required String projectName,
  }) {
    final executables = releaseDirectory
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.exe')
        .sorted((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()))
        .reversed;

    if (executables.isEmpty) {
      throw Exception(
        'No executables found in ${releaseDirectory.path}',
      );
    }

    return executables.firstWhere(
      (e) => p.basenameWithoutExtension(e.path) == projectName,
      orElse: () => executables.first,
    );
  }
}
