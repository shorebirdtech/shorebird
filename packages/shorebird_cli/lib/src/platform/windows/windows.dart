// cspell:words crashpad lfanew
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/platform/platform.dart' show Arch;
import 'package:shorebird_cli/src/shorebird_env.dart';

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
/// Flutter builds a Windows app for the architecture of the Dart its tool
/// runs on (`hostPlatform` in flutter_tools) and has no flag to pick another,
/// so an app shipped for both x64 and arm64 is built (and released and
/// patched) once on each kind of machine. That Dart is usually the machine's
/// own, but Flutter falls back to the x64 Dart on Windows on Arm when it
/// can't fetch the arm64 one, so this reads the architecture of Flutter's
/// Dart, and the machine's only when that can't be read.
Arch get windowsTargetArch {
  final dart = File(
    p.join(
      shorebirdEnv.flutterDirectory.path,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      'dart.exe',
    ),
  );
  return switch (peMachine(dart)) {
    _imageFileMachineArm64 => Arch.arm64,
    _imageFileMachineAmd64 => Arch.x86_64,
    _ => abi.hostArchitecture == 'arm64' ? Arch.arm64 : Arch.x86_64,
  };
}

const _imageFileMachineAmd64 = 0x8664;
const _imageFileMachineArm64 = 0xaa64;

/// The `IMAGE_FILE_MACHINE_*` value in the header of the Windows executable
/// [file], or null when [file] is missing or isn't one.
///
/// See https://learn.microsoft.com/windows/win32/debug/pe-format
int? peMachine(File file) {
  if (!file.existsSync()) return null;
  final RandomAccessFile handle;
  try {
    handle = file.openSync();
  } on FileSystemException {
    return null;
  }
  try {
    // The DOS header's e_lfanew, at 0x3c, is where the PE header starts:
    // the signature "PE\0\0" and then the 16-bit Machine field.
    final dosHeader = handle.readSync(0x40);
    if (dosHeader.length < 0x40 ||
        dosHeader[0] != 0x4d ||
        dosHeader[1] != 0x5a) {
      return null;
    }
    final peOffset = ByteData.sublistView(
      dosHeader,
    ).getUint32(0x3c, Endian.little);
    handle.setPositionSync(peOffset);
    final peHeader = handle.readSync(6);
    if (peHeader.length < 6 ||
        peHeader[0] != 0x50 ||
        peHeader[1] != 0x45 ||
        peHeader[2] != 0 ||
        peHeader[3] != 0) {
      return null;
    }
    return ByteData.sublistView(peHeader).getUint16(4, Endian.little);
  } on FileSystemException {
    return null;
  } finally {
    handle.closeSync();
  }
}

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
