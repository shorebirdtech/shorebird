import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';

class MissingGradleWrapperException implements Exception {
  const MissingGradleWrapperException(this.executablePath);

  final String executablePath;

  @override
  String toString() {
    return '''
Could not find $executablePath.
Make sure you have run "flutter build apk at least once.''';
  }
}

/// Mixin on [ShorebirdJavaMixin] which exposes methods for extracting
/// product flavors from the current app.
mixin ShorebirdFlavorMixin on ShorebirdJavaMixin {
  /// Return the set of product flavors configured for the app at [appRoot].
  /// Returns an empty set for apps that do not use product flavors.
  Future<Set<String>> extractProductFlavors(
    String appRoot, {
    Platform platform = const LocalPlatform(),
  }) async {
    // Flutter apps have android files in root/android
    // Flutter modules have android files in root/.android
    final androidRoot = [
      Directory(p.join(appRoot, 'android')),
      Directory(p.join(appRoot, '.android')),
    ].firstWhereOrNull((dir) => dir.existsSync());

    if (androidRoot == null) {
      return {};
    }

    final executable = platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final executablePath = p.join(androidRoot.path, executable);

    if (!File(executablePath).existsSync()) {
      throw MissingGradleWrapperException(p.relative(executablePath));
    }

    final javaHome = getJavaHome(platform);
    final result = await process.run(
      executablePath,
      ['app:tasks', '--all', '--console=auto'],
      runInShell: true,
      workingDirectory: androidRoot.path,
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
