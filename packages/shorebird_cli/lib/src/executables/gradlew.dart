// ignore_for_file: public_member_api_docs

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

enum GradleHandedErrors {
  unsupportedClassFileVersion;

  bool apply(ShorebirdProcessResult result) {
    switch (this) {
      case GradleHandedErrors.unsupportedClassFileVersion:
        return result.stderr.toString().contains(
              'Unsupported class file major version',
            );
    }
  }

  GradleProcessException toException() {
    switch (this) {
      case GradleHandedErrors.unsupportedClassFileVersion:
        final docLink = link(
          uri: Uri.parse(
            ShorebirdDocumentation.unsupportedClassFileVersionUrl,
          ),
          message: 'troubleshooting documentation',
        );
        return GradleProcessException('''
Unsupported class file major version.

This error is typically caused by a mismatch between the Java and Gradle's versions.

Check our $docLink for help. 
''');
    }
  }
}

/// {@template gradle_process_exception}
/// Thrown when the gradle sub-process fails.
/// {@endtemplate}
class GradleProcessException implements Exception {
  /// {@macro gradle_process_exception}
  const GradleProcessException(this.message);

  final String message;

  @override
  String toString() {
    return 'Gradle sub-process failed with error:\n$message';
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

/// Thrown when the gradle wrapper cannot be found.
/// This has been resolved on the master channel but
/// on the stable channel currently creating an app via
/// `flutter create` does not generate a gradle wrapper which
/// means we're not able to accurately detect flavors until
/// the user has run `flutter build apk` at least once.
class MissingGradleWrapperException implements Exception {
  const MissingGradleWrapperException(this.executablePath);

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
      runInShell: true,
      workingDirectory: p.dirname(executablePath),
      environment: {
        if (!javaHome.isNullOrEmpty) 'JAVA_HOME': javaHome!,
      },
    );

    if (result.exitCode != ExitCode.success.code) {
      for (final error in GradleHandedErrors.values) {
        if (error.apply(result)) {
          throw error.toException();
        }
      }
    }

    return result;
  }

  /// Returns whether the gradle wrapper exists at [projectRoot].
  bool exists(String projectRoot) =>
      File(p.join(projectRoot, 'android', executable)).existsSync();

  /// Return the version of the gradle wrapper at [projectRoot].
  Future<String> version(String projectRoot) async {
    final result = await _run(['--version'], projectRoot);

    // Tries to match version string in the output (e.g. "Gradle 7.6.3")
    final versionPattern = RegExp(r'Gradle (\d+\.\d+\.\d+)');
    final match = versionPattern.firstMatch(result.stdout.toString());

    return match?.group(1) ?? 'unknown';
  }

  /// Return the set of product flavors configured for the app at [projectRoot].
  /// Returns an empty set for apps that do not use product flavors.
  Future<Set<String>> productFlavors(String projectRoot) async {
    final result = await _run(
      ['app:tasks', '--all', '--console=auto'],
      projectRoot,
    );

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
