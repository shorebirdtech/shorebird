import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';

/// A reference to a [AndroidStudio] instance.
final androidStudioRef = create(AndroidStudio.new);

/// The [AndroidStudio] instance available in the current zone.
AndroidStudio get androidStudio => read(androidStudioRef);

/// A wrapper around Android Studio.
class AndroidStudio {
  /// The path to the Android Studio installation.
  String? get path {
    if (platform.isMacOS) {
      return _macOsPath;
    } else if (platform.isWindows) {
      return _windowsPath;
    } else if (platform.isLinux) {
      return _linuxPath;
    }

    return null;
  }

  String? get _windowsPath {
    final localAppData = platform.environment['LOCALAPPDATA'];
    if (!localAppData.isNullOrEmpty) {
      final cacheDir = Directory(p.join(localAppData!, 'Google'));
      if (cacheDir.existsSync()) {
        // This directory should contain, among other things,
        // AndroidStudioYYYY.N entries, where YYYY is the year and N is the
        // version number. Within these directories, there should be a .home
        // file that contains the path to the Android Studio installation. We
        // want to find the directory with the highest version number that
        // points to a valid installation and return that.
        final studioRegex = RegExp(r'AndroidStudio(\d+\.\d+)');
        final matchingDirectories = cacheDir
            .listSync()
            .whereType<Directory>()
            .where((dir) => studioRegex.hasMatch(dir.path));
        Version? highestVersion;
        final androidStudioVersionsToPaths = <Version, String>{};
        for (final directory in matchingDirectories) {
          final directoryName = p.basename(directory.path);
          final versionMatch = studioRegex.firstMatch(directoryName)!.group(1);
          final version = tryParseVersion(versionMatch!, strict: false);
          if (version == null) {
            logger.detail('Unable to parse version from $directoryName');
            continue;
          }

          final homeFile = File(p.join(directory.path, '.home'));
          if (!homeFile.existsSync()) {
            continue;
          }

          final String androidStudioPath;
          try {
            androidStudioPath = homeFile.readAsStringSync();
          } catch (e) {
            logger.detail('Unable to read $homeFile: $e');
            continue;
          }

          if (Directory(androidStudioPath).existsSync()) {
            androidStudioVersionsToPaths[version] = androidStudioPath;
            if (highestVersion == null || version > highestVersion) {
              highestVersion = version;
            }
          }
        }

        return androidStudioVersionsToPaths[highestVersion];
      }
    }

    final programFiles = platform.environment['PROGRAMFILES']!;
    final programFilesx86 = platform.environment['PROGRAMFILES(X86)']!;
    final candidateLocations = [
      p.join(programFiles, 'Android', 'Android Studio'),
      p.join(programFilesx86, 'Android', 'Android Studio'),
    ];
    return candidateLocations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }

  String? get _linuxPath {
    final home = platform.environment['HOME'] ?? '~';
    final candidateLocations = [
      p.join('/', 'snap', 'bin', 'android-studio'),
      p.join('/', 'opt', 'android-studio'),
      p.join(home, '.AndroidStudio'),
      p.join(home, '.cache', 'Google', 'AndroidStudio'),
    ];
    return candidateLocations.firstWhereOrNull((location) {
      return Directory(location).existsSync();
    });
  }

  String? get _macOsPath {
    final home = platform.environment['HOME'] ?? '~';
    final candidateLocations = [
      p.join(home, 'Applications', 'Android Studio.app', 'Contents'),
      p.join('/', 'Applications', 'Android Studio.app', 'Contents'),
    ];
    return candidateLocations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }
}
