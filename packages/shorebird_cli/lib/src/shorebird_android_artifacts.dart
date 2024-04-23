import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Throw when multiple artifacts are found in the build directory.
class MultipleArtifactsFoundException implements Exception {
  MultipleArtifactsFoundException({
    required this.buildDir,
    required this.foundArtifacts,
  });

  final String buildDir;
  final List<FileSystemEntity> foundArtifacts;

  @override
  String toString() {
    return 'Multiple artifacts found in $buildDir: '
        '${foundArtifacts.map((e) => e.path)}';
  }
}

extension on String {
  String get artifactId => replaceAll(RegExp(r'\W'), '').toLowerCase();
}

final shorebirdAndroidArtifactsRef = create(ShorebirdAndroidArtifacts.new);

ShorebirdAndroidArtifacts get shorebirdAndroidArtifacts =>
    read(shorebirdAndroidArtifactsRef);

/// Mixin on [ShorebirdCommand] which exposes methods
// to find the artifacts generated for android
class ShorebirdAndroidArtifacts {
  /// Find the artifact in the build directory.
  String? findArtifact({
    required String artifactName,
    required String buildDir,
  }) {
    // Remove all non characters and digits from the artifact name.
    final artifactId = artifactName.artifactId;

    final directory = Directory(buildDir);
    if (!directory.existsSync()) {
      return null;
    }

    final allFiles = directory.listSync();
    final candidates = allFiles.where((file) {
      final fileName = p.basename(file.path);
      return fileName.artifactId == artifactId;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    } else if (candidates.length > 1) {
      throw MultipleArtifactsFoundException(
        buildDir: buildDir,
        foundArtifacts: candidates,
      );
    } else {
      return candidates.first.path;
    }
  }

  /// Find the app bundle in the build directory.
  String? findAppBundle({
    required String projectPath,
    required String? flavor,
  }) {
    final buildDir = p.join(
      projectPath,
      'build',
      'app',
      'outputs',
      'bundle',
      flavor != null ? '${flavor}Release' : 'release',
    );

    final artifactName =
        flavor == null ? 'app-release.aab' : 'app-$flavor-release.aab';

    return findArtifact(
      buildDir: buildDir,
      artifactName: artifactName,
    );
  }

  /// Find the apk in the build directory.
  String? findApk({
    required String projectPath,
    required String? flavor,
  }) {
    final buildDir = p.join(
      projectPath,
      'build',
      'app',
      'outputs',
      'flutter-apk',
    );

    final artifaceName =
        flavor == null ? 'app-release.apk' : 'app-$flavor-release.apk';

    return findArtifact(
      buildDir: buildDir,
      artifactName: artifaceName,
    );
  }
}
