import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';

/// Mixin on [ShorebirdJavaMixin] which exposes methods
/// to extract the release version from an app bundle.
mixin ShorebirdReleaseVersionMixin on ShorebirdJavaMixin {
  /// Extract the release version from an appbundle.
  Future<String> extractReleaseVersionFromAppBundle(
    String appBundlePath,
  ) async {
    await cache.updateAll();
    const bundleToolJar = 'bundletool.jar';
    final bundleTool = p.join(
      cache.getArtifactDirectory(bundleToolJar).path,
      bundleToolJar,
    );
    final baseArguments = [
      '-jar',
      bundleTool,
      'dump',
      'manifest',
      '--bundle',
      appBundlePath,
    ];
    final versionNameArguments = [
      ...baseArguments,
      '--xpath',
      '/manifest/@android:versionName'
    ];
    final versionCodeArguments = [
      ...baseArguments,
      '--xpath',
      '/manifest/@android:versionCode'
    ];

    final javaPath = getJavaPath();
    final results = await Future.wait([
      process.run(
        'java',
        versionNameArguments,
        runInShell: true,
        environment: {
          if (javaPath != null) 'JAVA_HOME': javaPath,
        },
      ),
      process.run(
        'java',
        versionCodeArguments,
        runInShell: true,
        environment: {
          if (javaPath != null) 'JAVA_HOME': javaPath,
        },
      )
    ]);

    final versionNameResult = results[0];
    final versionCodeResult = results[1];
    if (versionNameResult.exitCode != 0) {
      throw Exception(
        '''Failed to extract version name from app bundle: ${versionNameResult.stderr}''',
      );
    }
    if (versionCodeResult.exitCode != 0) {
      throw Exception(
        '''Failed to extract version code from app bundle: ${versionCodeResult.stderr}''',
      );
    }

    final versionName = (versionNameResult.stdout as String).trim();
    final versionCode = (versionCodeResult.stdout as String).trim();

    return '$versionName+$versionCode';
  }
}
