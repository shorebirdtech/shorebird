import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/command.dart';

/// Mixin on [ShorebirdCommand] which exposes methods for extracting
/// product flavors from the current app.
mixin ShorebirdFlavorMixin on ShorebirdCommand {
  /// Return the set of product flavors configured for the app at [path].
  /// Returns an empty set for apps that do not use product flavors.
  Future<Set<String>> extractProductFlavors(
    String path, {
    Platform platform = const LocalPlatform(),
  }) async {
    final executable = platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final androidStudioPath = _getAndroidStudioPath(platform);
    final javaPath = androidStudioPath != null
        ? _getJavaPath(androidStudioPath, platform)
        : null;
    final result = await process.run(
      p.join(path, 'android', executable),
      ['app:tasks', '--all', '--console=auto'],
      runInShell: true,
      workingDirectory: p.join(path, 'android'),
      environment: {
        if (javaPath != null) 'JAVA_HOME': javaPath,
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
        final variant = match.group(1)!.toLowerCase();
        if (!variant.endsWith('test')) {
          variants.add(variant);
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
        p.join(home, '.AndroidStudio'),
        p.join(home, '.cache', 'Google', 'AndroidStudio'),
      ];
      return candidateLocations.firstWhereOrNull((location) {
        return Directory(location).existsSync();
      });
    }

    return null;
  }

  String? _getJavaPath(String directory, Platform platform) {
    if (platform.isMacOS) {
      final candidateLocations = [
        p.join(directory, 'jbr', 'Contents', 'Home'),
        p.join(directory, 'jre', 'Contents', 'Home'),
        p.join(directory, 'jre', 'jdk', 'Contents', 'Home')
      ];

      return candidateLocations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    final candidateLocations = [
      p.join(directory, 'jbr'),
      p.join(directory, 'jre'),
    ];

    return candidateLocations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }
}
