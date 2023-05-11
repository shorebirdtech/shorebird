import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/command.dart';

/// Mixin on [ShorebirdCommand] which exposes methods
/// for determining the java path.
mixin ShorebirdJavaMixin on ShorebirdCommand {
  String? getJavaExecutable([Platform platform = const LocalPlatform()]) {
    final javaPath = getJavaPath(platform);
    if (javaPath == null) return null;
    if (platform.isWindows) {
      return p.join(javaPath, 'java.exe');
    } else {
      return p.join(javaPath, 'java');
    }
  }

  String? getJavaPath([Platform platform = const LocalPlatform()]) {
    if (platform.environment.containsKey('JAVA_HOME')) {
      return platform.environment['JAVA_HOME'];
    }

    final androidStudioPath = _getAndroidStudioPath(platform);
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
      p.join(androidStudioPath, 'jbr', 'bin'),
      p.join(androidStudioPath, 'jre', 'bin'),
    ];

    return candidateLocations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }

  String? _getAndroidStudioPath(Platform platform) {
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
