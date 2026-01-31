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

/// Executables bundled with Flutter Windows builds that are not the app.
const defaultIgnoredExecutables = {'crashpad_handler.exe'};

/// A class that provides Windows-specific functionality.
class Windows {
  /// Returns the selected application `.exe` from [releaseDirectory].
  /// If [projectName] is provided, searches for an exact match first.
  /// Falls back to returning the most recently modified executable,
  /// excluding [ignoredExecutables] (defaults to [defaultIgnoredExecutables]).
  ///
  /// Note: when files are extracted from a zip, they may all have similar
  /// timestamps, making the mtime fallback unreliable. Prefer passing
  /// [projectName] when available.
  File findExecutable({
    required Directory releaseDirectory,
    String? projectName,
    Set<String> ignoredExecutables = defaultIgnoredExecutables,
  }) {
    final executables = releaseDirectory
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.exe')
        .where(
          (f) => !ignoredExecutables.contains(p.basename(f.path)),
        )
        .sorted((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    if (executables.isEmpty) {
      throw Exception('No executables found in ${releaseDirectory.path}');
    }

    return executables.firstWhere(
      (e) => p.basenameWithoutExtension(e.path) == projectName,
      orElse: () => executables.first,
    );
  }
}
