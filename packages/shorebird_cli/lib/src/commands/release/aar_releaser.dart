import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:io/io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template aar_releaser}
/// Functions to create an aar release.
/// {@endtemplate}
class AarReleaser extends Releaser {
  /// {@macro aar_releaser}
  AarReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// The build number of the aar (1.0). Forwarded to the --build-number
  /// argument of the flutter build aar command.
  String get buildNumber => argResults['build-number'] as String;

  /// The architectures to build the aar for.
  Set<Arch> get architectures => (argResults['target-platform'] as List<String>)
      .map(
        (platform) => AndroidArch.availableAndroidArchs.firstWhere(
          (arch) => arch.targetPlatformCliArg == platform,
        ),
      )
      .toSet();

  @override
  ReleaseType get releaseType => ReleaseType.aar;

  @override
  String get supplementPlatformSubdir => 'android';

  @override
  String get supplementArtifactArch => 'aar_supplement';

  @override
  String get artifactDisplayName => 'Android archive';

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }

    if (shorebirdEnv.androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      throw ProcessExit(ExitCode.config.code);
    }
  }

  @override
  Future<void> assertArgsAreValid() async {
    // --release-version is optional for AAR releases. If omitted, we default
    // to the current git commit hash (short form).
    //
    // TODO(eseidel): Add a minimum Flutter version check here once we know
    // which Flutter version first supports SHOREBIRD_RELEASE_VERSION. The
    // env var is silently ignored by older Flutter versions, so the version
    // won't be baked into the yaml and the updater will fall back to the
    // host app's version — which defeats the purpose for add-to-app users.
    await assertObfuscationIsSupported();
  }

  /// Returns the release version to use. If --release-version was provided,
  /// uses that. Otherwise defaults to the current git commit short hash.
  Future<String> _resolveReleaseVersion() async {
    if (argResults.wasParsed('release-version')) {
      return argResults['release-version'] as String;
    }

    final result = await process.run('git', ['rev-parse', '--short', 'HEAD']);
    if (result.exitCode != 0) {
      logger.err(
        'Failed to determine git revision. '
        'Provide --release-version explicitly or run from a git repository.',
      );
      throw ProcessExit(ExitCode.software.code);
    }
    final gitHash = (result.stdout as String).trim();
    logger.info(
      'No --release-version provided, using git hash: '
      '${lightCyan.wrap(gitHash)}',
    );
    return gitHash;
  }

  /// The resolved release version, cached after first resolution.
  String? _releaseVersion;

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    // Resolve release version before building so we can pass it to Flutter
    // via the SHOREBIRD_RELEASE_VERSION environment variable.
    _releaseVersion ??= await _resolveReleaseVersion();

    final base64PublicKey = await getEncodedPublicKey();
    final buildArgs = [...argResults.forwardedArgs];
    addSplitDebugInfoDefault(buildArgs);
    addObfuscationMapArgs(buildArgs);

    await artifactBuilder.buildAar(
      buildNumber: buildNumber,
      targetPlatforms: architectures,
      args: buildArgs,
      base64PublicKey: base64PublicKey,
      releaseVersion: _releaseVersion,
    );

    verifyObfuscationMap();

    // Copy release AAR to a new directory to avoid overwriting with
    // subsequent patch builds.
    final sourceLibraryDirectory = Directory(
      ShorebirdAndroidArtifacts.aarLibraryPath,
    );
    final targetLibraryDirectory = Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
    );
    await copyPath(sourceLibraryDirectory.path, targetLibraryDirectory.path);

    return targetLibraryDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    _releaseVersion ??= await _resolveReleaseVersion();
    return _releaseVersion!;
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final extractAarProgress = logger.progress('Creating artifacts');
    final extractedAarDir = await shorebirdAndroidArtifacts.extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: extractFileToDisk,
    );
    extractAarProgress.complete();

    await codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      platform: releaseType.releasePlatform,
      aarPath: ShorebirdAndroidArtifacts.aarArtifactPath(
        packageName: shorebirdEnv.androidPackageName!,
        buildNumber: buildNumber,
      ),
      extractedAarDir: extractedAarDir.path,
      architectures: architectures,
    );

    await uploadSupplementArtifact(appId: appId, releaseId: release.id);
  }

  @override
  String get postReleaseInstructions {
    final targetLibraryDirectory = Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
    );

    return '''

Your next steps:

1. Add the aar repo and Shorebird's maven url to your app's settings.gradle:

Note: The maven url needs to be a relative path from your settings.gradle file to the aar library. The code below assumes your Flutter module is in a sibling directory of your Android app.

${lightCyan.wrap('''
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
+       maven {
+           url '../${p.basename(shorebirdEnv.getShorebirdProjectRoot()!.path)}/${p.relative(targetLibraryDirectory.path)}'
+       }
+       maven {
-           url 'https://storage.googleapis.com/download.flutter.io'
+           url 'https://download.shorebird.dev/download.flutter.io'
+       }
    }
}
''')}

2. Add this module as a dependency in your app's build.gradle:
${lightCyan.wrap('''
dependencies {
  // ...
  releaseImplementation '${shorebirdEnv.androidPackageName}:flutter_release:$buildNumber'
  // ...
}''')}
''';
  }
}
