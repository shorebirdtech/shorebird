import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// Exception thrown when the Gradle version is incompatible.
class IncompatibleGradleException implements Exception {
  /// The error pattern used to identify the exception.
  static const errorPattern = 'Unsupported class file major version';

  @override
  String toString() {
    final docLink = link(
      uri: Uri.parse(unsupportedClassFileVersionUrl),
      message: 'troubleshooting documentation',
    );
    return '''
Unsupported class file major version.

This error is typically caused by a mismatch between the Java and Gradle's versions.

Check our $docLink for help. 
''';
  }
}

/// {@template missing_android_project_exception}
/// Thrown when the Flutter project does not have
/// Android configured as a platform.
/// {@endtemplate}
class MissingAndroidProjectException implements Exception {
  /// {@macro missing_android_project_exception}
  const MissingAndroidProjectException(this.projectRoot);

  /// Expected path for the Android project.
  final String projectRoot;

  @override
  String toString() {
    return '''
Could not find an android project in $projectRoot.
To add android, run "flutter create . --platforms android"''';
  }
}

/// {@template missing_gradle_wrapper_exception}
/// Thrown when the gradle wrapper cannot be found.
/// This has been resolved on the master channel but
/// on the stable channel currently creating an app via
/// `flutter create` does not generate a gradle wrapper which
/// means we're not able to accurately detect flavors until
/// the user has run `flutter build apk` at least once.
/// {@endtemplate}
class MissingGradleWrapperException implements Exception {
  /// {@macro missing_gradle_wrapper_exception}
  const MissingGradleWrapperException(this.executablePath);

  /// The path to the gradle wrapper executable.
  final String executablePath;

  @override
  String toString() {
    return '''
Could not find $executablePath.
Make sure you have run "flutter build apk" at least once.''';
  }
}

/// A reference to a [Gradlew] instance.
final gradlewRef = create(Gradlew.new);

/// The [Gradlew] instance available in the current zone.
Gradlew get gradlew => read(gradlewRef);

/// A wrapper around the gradle wrapper (gradlew).
class Gradlew {
  /// The name of the executable.
  String get executable => platform.isWindows ? 'gradlew.bat' : 'gradlew';

  Future<ShorebirdProcessResult> _run(
    List<String> args,
    String projectRoot,
  ) async {
    final javaHome = java.home;
    final androidRoot = Directory(p.join(projectRoot, 'android'));

    if (!androidRoot.existsSync()) {
      throw MissingAndroidProjectException(projectRoot);
    }

    final executableFile = File(p.join(androidRoot.path, executable));

    if (!executableFile.existsSync()) {
      throw MissingGradleWrapperException(p.relative(executableFile.path));
    }

    final executablePath = executableFile.path;
    final result = await process.run(
      executablePath,
      args,
      // Never run in shell because we always have a fully resolved
      // executable path.
      runInShell: false,
      workingDirectory: p.dirname(executablePath),
      environment: {if (!javaHome.isNullOrEmpty) 'JAVA_HOME': javaHome!},
    );

    if (result.exitCode != ExitCode.success.code) {
      if (result.stderr.toString().contains(
        IncompatibleGradleException.errorPattern,
      )) {
        throw IncompatibleGradleException();
      }
    }

    return result;
  }

  Future<int> _stream(List<String> args, String projectRoot) async {
    final javaHome = java.home;
    final androidRoot = Directory(p.join(projectRoot, 'android'));

    if (!androidRoot.existsSync()) {
      throw MissingAndroidProjectException(projectRoot);
    }

    final executableFile = File(p.join(androidRoot.path, executable));

    if (!executableFile.existsSync()) {
      throw MissingGradleWrapperException(p.relative(executableFile.path));
    }

    final executablePath = executableFile.path;
    return process.stream(
      executablePath,
      args,
      // Never run in shell because we always have a fully resolved
      // executable path.
      runInShell: false,
      workingDirectory: p.dirname(executablePath),
      environment: {if (!javaHome.isNullOrEmpty) 'JAVA_HOME': javaHome!},
    );
  }

  /// Returns whether the gradle wrapper exists at [projectRoot].
  bool exists(String projectRoot) =>
      File(p.join(projectRoot, 'android', executable)).existsSync();

  /// Return the version of the gradle wrapper at [projectRoot].
  Future<String> version(String projectRoot) async {
    final result = await _run(['--version'], projectRoot);

    // Tries to match version string in the output (e.g. "Gradle 7.6.3" or
    // "Grade 8.3")
    final versionPattern = RegExp(r'Gradle (\d+\.\d+(\.\d+)?)');
    final match = versionPattern.firstMatch(result.stdout.toString());

    return match?.group(1) ?? 'unknown';
  }

  /// Whether the gradle daemon is available at [projectRoot].
  /// Command: `./gradlew --status`
  Future<bool> isDaemonAvailable(String projectRoot) async {
    // Sample output:
    // PID   STATUS   INFO
    // 30047 IDLE     8.11.1
    // 26397 STOPPED  (after the daemon registry became unreadable)
    // 23432 STOPPED  (by user or operating system)
    final status = await _run(['--status'], projectRoot);
    if (status.exitCode != 0) {
      throw Exception('Unable to determine gradle daemon status');
    }

    // If we have a daemon that is either IDLE or BUSY then subsequent
    // gradle commands will be faster.
    return status.stdout.toString().contains('IDLE') ||
        status.stdout.toString().contains('BUSY');
  }

  /// Starts the daemon if not running at [projectRoot].
  /// Command: `./gradlew --daemon`
  Future<void> startDaemon(String projectRoot) async {
    final exitCode = await _stream(['--daemon'], projectRoot);
    if (exitCode != 0) {
      throw Exception('Unable to start gradle daemon');
    }
  }

  /// Return the set of product flavors configured for the app at [projectRoot].
  /// Returns an empty set for apps that do not use product flavors.
  Future<Set<String>> productFlavors(String projectRoot) async {
    final result = await _run([
      'app:tasks',
      '--all',
      '--console=auto',
    ], projectRoot);

    if (result.exitCode != 0) {
      throw Exception('${result.stdout}\n${result.stderr}');
    }

    final variants = <String>{};
    final assembleTaskPattern = RegExp(r'assemble(\S+)');
    for (final task in '${result.stdout}'.split('\n')) {
      final match = assembleTaskPattern.matchAsPrefix(task);
      if (match != null) {
        final variant = match.group(1)!;
        if (!variant.toLowerCase().endsWith('test')) {
          // Gradle flavor name transformation seems to work with the following
          // rules:
          //  - If the flavor starts with at least two capital letters, use
          //    as-is
          //  - Otherwise, transform to camel case
          //
          // Example:
          // development -> development
          // developmentWithAnotherContext -> developmentWithAnotherContext
          //
          // Development -> development
          // DevelopmentWithAnotherContext -> developmentWithAnotherContext
          //
          // QA -> QA
          // QAInBrazil -> QAInBrazil
          // QAOver9000 -> QAOver9000
          if (variant.areFirstTwoLetterUppercase) {
            variants.add(variant);
          } else {
            variants.add(variant[0].toLowerCase() + variant.substring(1));
          }
        }
      }
    }

    /// Iterate through all variants and compare them to each other. If one
    /// variant is a prefix of another, then it is a product flavor.
    /// For example, if the variants are:
    /// `debug`, `developmentDebug`, and `productionDebug`,
    /// then `development`, and `production` are product flavors.
    final productFlavors = <String>{};
    for (final variant in variants) {
      final match = variants.firstWhereOrNull(
        (v) => v.startsWith(variant) && v != variant,
      );
      if (match != null) productFlavors.add(variant);
    }
    return productFlavors;
  }
}

extension on String {
  /// Returns true when the string starts with at least two upper case letters
  ///
  /// Gradle flavors that are not capital case will not be transformed
  /// to camel case and should be used as is. So this method helps to identify
  /// those cases.
  ///
  /// Example:
  /// ```dart
  /// 'Test'.startsWithUpperCaseLetters; // false
  /// 'TEST'.startsWithUpperCaseLetters; // true
  /// 'TESTING'.startsWithUpperCaseLetters; // true
  /// ```
  bool get areFirstTwoLetterUppercase {
    if (length >= 2) {
      return this[0].isUpperCase() && this[1].isUpperCase();
    }
    return false;
  }
}
