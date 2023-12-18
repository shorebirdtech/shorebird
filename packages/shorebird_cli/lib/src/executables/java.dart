import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';

/// A reference to a [Java] instance.
final javaRef = create(Java.new);

/// The [Java] instance available in the current zone.
Java get java => read(javaRef);

/// A wrapper around all java related functionality.
class Java {
  /// Returns the path to the user's Java executable, if one is found.
  ///
  /// Our goal is to match the behavior of the flutter tool. As per the docs at
  /// https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/android/java.dart#L45-L54,
  /// we search for Java in the following places, in order:
  ///
  /// 1. The runtime environment bundled with Android Studio;
  /// 2. The runtime environment found in the JAVA_HOME env variable, if set; or
  /// 3. The java binary found on PATH.
  String? get executable {
    if (home.isNullOrEmpty) {
      return osInterface.which('java');
    }

    return p.join(home!, _javaExecutablePath);
  }

  /// Returns a path to the user's JDK. If one is not found, returns `null`.
  ///
  /// This first looks for the Java bundled with Android Studio, then the
  /// JAVA_HOME environment variable.
  String? get home {
    if (!_androidStudioJavaPath.isNullOrEmpty) {
      return _androidStudioJavaPath;
    }

    final environmentJava = platform.environment['JAVA_HOME'];
    if (!environmentJava.isNullOrEmpty) {
      return environmentJava;
    }

    return null;
  }

  /// Returns the path to the java executable relative to the Java home dir.
  String get _javaExecutablePath =>
      p.join('bin', platform.isWindows ? 'java.exe' : 'java');

  String? get _androidStudioJavaPath {
    final androidStudioPath = androidStudio.path;
    if (androidStudioPath == null) return null;
    if (platform.isMacOS) {
      final candidateLocations = [
        p.join(androidStudioPath, 'jbr', 'Contents', 'Home'),
        p.join(androidStudioPath, 'jre', 'Contents', 'Home'),
        p.join(androidStudioPath, 'jre', 'jdk', 'Contents', 'Home'),
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
}
