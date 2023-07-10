import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';

// A reference to a [Java] instance.
final javaRef = create(Java.new);

// The [Java] instance available in the current zone.
Java get java => read(javaRef);

/// A wrapper around all java related functionality.
class Java {
  /// Returns the path to the java executable.
  String? executable() {
    if (!platform.isWindows) return 'java';

    final javaHome = home();
    if (javaHome == null) return null;
    return p.join(javaHome, 'bin', 'java.exe');
  }

  /// Returns the JAVA_HOME environment variable if set.
  /// Otherwise, returns the location where the Android Studio JDK/JRE is installed.
  String? home() {
    if (platform.environment.containsKey('JAVA_HOME')) {
      return platform.environment['JAVA_HOME'];
    }

    final androidStudioPath = _getAndroidStudioPath();
    if (androidStudioPath == null) return null;
    if (platform.isMacOS) {
      final candidateLocations = [
        p.join(androidStudioPath, 'jbr', 'Contents', 'Home'),
        p.join(androidStudioPath, 'jre', 'Contents', 'Home'),
        p.join(androidStudioPath, 'jre', 'jdk', 'Contents', 'Home')
      ];

      return candidateLocations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    final candidateLocations = [
      p.join(androidStudioPath, 'jbr'),
      p.join(androidStudioPath, 'jre'),
    ];

    return candidateLocations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }

  String? _getAndroidStudioPath() {
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
