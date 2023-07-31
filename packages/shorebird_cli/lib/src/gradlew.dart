import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';

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

  String executablePath(String projectPath) {
    // Flutter apps have android files in root/android
    // Flutter modules have android files in root/.android
    final androidRoot = [
      Directory(p.join(projectPath, 'android')),
      Directory(p.join(projectPath, '.android')),
    ].firstWhereOrNull((dir) => dir.existsSync());

    if (androidRoot == null) throw MissingGradleWrapperException(executable);

    final executableFile = File(p.join(androidRoot.path, executable));

    if (!executableFile.existsSync()) {
      throw MissingGradleWrapperException(p.relative(executableFile.path));
    }

    return executableFile.path;
  }

  /// Return the set of product flavors configured for the app at [projectPath].
  /// Returns an empty set for apps that do not use product flavors.
  Future<Set<String>> productFlavors(String projectPath) async {
    final javaHome = java.home;
    final gradlePath = executablePath(projectPath);
    final result = await process.run(
      executablePath(projectPath),
      ['app:tasks', '--all', '--console=auto'],
      runInShell: true,
      workingDirectory: p.dirname(gradlePath),
      environment: {
        if (javaHome != null) 'JAVA_HOME': javaHome,
      },
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
          variants.add(variant[0].toLowerCase() + variant.substring(1));
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
