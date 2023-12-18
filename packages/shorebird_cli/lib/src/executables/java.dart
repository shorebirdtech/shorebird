import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';

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

  /// Returns the path to the java executable relative to the Java home dir.
  String get _javaExecutable =>
      platform.isWindows ? p.join('bin', 'java.exe') : 'java';

  /// Returns the path to the user's JDK, if one is found.
  ///
  /// Our goal is to match the behavior of the flutter tool. As per the docs at
  /// https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/android/java.dart#L45-L54,
  /// we search for Java in the following places, in order:
  ///
  /// 1. The runtime environment bundled with Android Studio;
  /// 2. The runtime environment found in the JAVA_HOME env variable, if set; or
  /// 3. The java binary found on PATH.
  String? get home {
    if (_isValidJava(_androidStudioJavaPath)) {
      print('using bundled java at $_androidStudioJavaPath');
      return _androidStudioJavaPath;
    }

    final environmentJava = platform.environment['JAVA_HOME'];
    if (_isValidJava(environmentJava)) {
      print('using java found in JAVA_HOME at $environmentJava');
      return environmentJava;
    }

    final pathJava = osInterface.which('java');
    if (!pathJava.isNullOrEmpty && _javaVersionOutput(pathJava!) != null) {
      print('using java found on PATH at $pathJava');
      return pathJava;
    }

    print('no java found');

    return null;
  }

  bool _isValidJava(String? javaHomePath) {
    if (javaHomePath.isNullOrEmpty) {
      return false;
    }

    final fullPath = p.join(javaHomePath!, _javaExecutable);
    final version = _javaVersionOutput(fullPath);
    return !version.isNullOrEmpty;
  }

  String? _javaVersionOutput(String executablePath) {
    final ShorebirdProcessResult result;
    try {
      result = process.runSync(executablePath, ['-version'], runInShell: true);
    } catch (e) {
      logger.detail('Error running java -version: $e');
      return null;
    }

    if (result.exitCode != 0) {
      return null;
    }

    final stdout = result.stdout as String?;
    final stderr = result.stderr as String?;

    if (!stdout.isNullOrEmpty) {
      return stdout;
    }

    // Windows java -version output goes to stderr.
    return stderr;
  }

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
