// cspell:words crashpad
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/platform/platform.dart' show Arch;

/// The primary release artifact architecture for x64 Windows releases.
/// This is a zipped copy of `build/windows/x64/runner/Release`, which is
/// produced by the `flutter build windows --release` command. It contains, at
/// its top level:
///   - flutter.dll
///   - app.exe (where `app` is the name of the Flutter app)
///   - data/, which contains flutter assets and the app.so file
///
/// An arm64 release's is [windowsReleaseArtifactArch] of [Arch.arm64].
const primaryWindowsReleaseArtifactArch = 'win_archive';

/// The architecture `flutter build windows` builds for on this machine.
///
/// Flutter builds a Windows app for the host's own architecture and has no
/// flag to pick another, so an app shipped for both x64 and arm64 is built
/// (and released and patched) once on each kind of machine.
Arch get windowsTargetArch =>
    abi.hostArchitecture == 'arm64' ? Arch.arm64 : Arch.x86_64;

/// The release artifact arch of the zipped `runner/Release` directory built
/// for [arch]. x64 keeps the name it had before arm64 was supported.
String windowsReleaseArtifactArch(Arch arch) => switch (arch) {
  Arch.arm64 => 'win_archive_arm64',
  _ => primaryWindowsReleaseArtifactArch,
};

/// The release artifact arch of the supplement built for [arch].
String windowsSupplementArtifactArch(Arch arch) => switch (arch) {
  Arch.arm64 => 'windows_supplement_arm64',
  _ => 'windows_supplement',
};

/// The directory under `build/windows/` that Flutter builds [arch] into.
String windowsBuildDirectoryName(Arch arch) => switch (arch) {
  Arch.arm64 => 'arm64',
  _ => 'x64',
};

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
