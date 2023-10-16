import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';

/// A reference to a [Java] instance.
final javaRef = create(Java.new);

/// The [Java] instance available in the current zone.
Java get java => read(javaRef);

/// A wrapper around all java related functionality.
class Java {
  /// Returns the path to the java executable.
  String? get executable {
    if (!platform.isWindows) return 'java';

    final javaHome = home;
    if (javaHome == null) return null;
    return p.join(javaHome, 'bin', 'java.exe');
  }

  /// Returns the path to the user's JDK, if one is found.
  ///
  /// Our goal is to match the behavior of the flutter tool. As per the docs at
  /// https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/android/java.dart#L45-L54,
  /// we search for Java in the following places, in order:
  ///
  /// 1. the runtime environment bundled with Android Studio;
  /// 2. the runtime environment found in the JAVA_HOME env variable, if set; or
  /// 3. the java binary found on PATH.
  String? get home =>
      _androidStudioJavaPath ??
      platform.environment['JAVA_HOME'] ??
      osInterface.which('java');

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
