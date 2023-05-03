import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/command.dart';

mixin ShorebirdFlavorMixin on ShorebirdCommand {
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

    if (result.exitCode != 0) throw Exception('${result.stderr}');

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

    final productFlavors = <String>{};
    for (final variant1 in variants) {
      for (final variant2 in variants) {
        if (variant2.startsWith(variant1) && variant2 != variant1) {
          final buildType = variant2.substring(variant1.length);
          if (variants.contains(buildType)) {
            productFlavors.add(variant1);
          }
        }
      }
    }
    return productFlavors;
  }

  String? _getAndroidStudioPath(Platform platform) {
    final home = platform.environment['HOME'] ?? '~';
    if (platform.isMacOS) {
      final locations = [
        p.join('/', 'Applications', 'Android Studio.app', 'Contents'),
        p.join(home, 'Applications', 'Android Studio.app', 'Contents'),
      ];
      return locations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    if (platform.isWindows) {
      final programFiles = platform.environment['PROGRAMFILES']!;
      final programFilesx86 = platform.environment['PROGRAMFILES(X86)']!;
      final locations = [
        p.join(programFiles, 'Android', 'Android Studio'),
        p.join(programFilesx86, 'Android', 'Android Studio'),
      ];
      return locations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    if (platform.isLinux) {
      final locations = [
        p.join(home, '.AndroidStudio'),
        p.join(home, '.cache', 'Google', 'AndroidStudio'),
      ];
      return locations.firstWhereOrNull((location) {
        return Directory(location).existsSync();
      });
    }

    return null;
  }

  String? _getJavaPath(String directory, Platform platform) {
    if (platform.isMacOS) {
      final locations = [
        p.join(directory, 'jbr', 'Contents', 'Home'),
        p.join(directory, 'jre', 'Contents', 'Home'),
        p.join(directory, 'jre', 'jdk', 'Contents', 'Home')
      ];

      return locations.firstWhereOrNull(
        (location) => Directory(location).existsSync(),
      );
    }

    final locations = [
      p.join(directory, 'jbr'),
      p.join(directory, 'jre'),
    ];

    return locations.firstWhereOrNull(
      (location) => Directory(location).existsSync(),
    );
  }
}
