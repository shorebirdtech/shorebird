import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';

/// A reference to a [AndroidStudio] instance.
final androidStudioRef = create(AndroidStudio.new);

/// The [AndroidStudio] instance available in the current zone.
AndroidStudio get androidStudio => read(androidStudioRef);

class AndroidStudio {
  String? path() {
    final home = platform.environment['HOME'] ?? '~';
    if (platform.isMacOS) {
      final candidateLocations = [
        p.join(home, 'Applications', 'Android Studio.app', 'Contents'),
        p.join('/', 'Applications', 'Android Studio.app', 'Contents'),
      ];
      return candidateLocations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    if (platform.isWindows) {
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

    if (platform.isLinux) {
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

    return null;
  }
}
