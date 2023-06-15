import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_aar_command}
/// `shorebird patch aar`
/// Create a patch for an Android archive release.
/// {@endtemplate}
class PatchAarCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin,
        ShorebirdArtifactMixin {
  /// {@macro patch_aar_command}
  PatchAarCommand({
    super.cache,
    super.validators,
    HashFunction? hashFn,
    UnzipFn? unzipFn,
    http.Client? httpClient,
    AarDiffer? aarDiffer,
  })  : _aarDiffer = aarDiffer ?? AarDiffer(),
        _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _unzipFn = unzipFn ?? extractFileToDisk,
        _httpClient = httpClient ?? http.Client() {
    argParser
      ..addOption(
        'build-number',
        help: 'The build number of the module (e.g. "1.0.0").',
        defaultsTo: '1.0',
      )
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the Android app that is using this module.''',
        mandatory: true,
      )
      ..addOption(
        'channel',
        help: 'The channel the patch should be promoted to (e.g. "stable").',
        allowed: ['stable'],
        allowedHelp: {
          'stable': 'The stable channel which is consumed by production apps.'
        },
        defaultsTo: 'stable',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Patch without confirmation if there are no errors.',
        negatable: false,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      );
  }

  @override
  String get name => 'aar';

  @override
  String get description =>
      'Publish new patches for a specific Android archive release to Shorebird';

  final AarDiffer _aarDiffer;
  final HashFunction _hashFn;
  final UnzipFn _unzipFn;
  final http.Client _httpClient;

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    await cache.updateAll();

    if (androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

    final flavor = results['flavor'] as String?;
    final buildNumber = results['build-number'] as String;
    final releaseVersion = results['release-version'] as String;

    final shorebirdYaml = ShorebirdEnvironment.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final buildProgress = logger.progress('Building patch');
    try {
      await buildAar(flavor: flavor, buildNumber: buildNumber);
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    if (dryRun) {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
      return ExitCode.success.code;
    }

    const platformName = 'android';
    final channelName = results['channel'] as String;

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    final flutterRevisionProgress = logger.progress(
      'Fetching Flutter revision',
    );
    final String shorebirdFlutterRevision;
    try {
      shorebirdFlutterRevision = await getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
    }

    if (release.flutterRevision != shorebirdFlutterRevision) {
      logger
        ..err('''
Flutter revision mismatch.

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: ${release.flutterRevision}
Current Flutter Revision: $shorebirdFlutterRevision
''')
        ..info(
          '''
Either create a new release using:
  ${lightCyan.wrap('shorebird release aar')}

Or downgrade your Flutter version and try again using:
  ${lightCyan.wrap('cd ${ShorebirdEnvironment.flutterDirectory.path}')}
  ${lightCyan.wrap('git checkout ${release.flutterRevision}')}

Shorebird plans to support this automatically, let us know if it's important to you:
https://github.com/shorebirdtech/shorebird/issues/472
''',
        );
      return ExitCode.software.code;
    }

    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      releaseId: release.id,
      architectures: architectures,
      platform: platformName,
    );

    final releaseAarArtifact = await codePushClientWrapper.getReleaseArtifact(
      releaseId: release.id,
      arch: 'aar',
      platform: platformName,
    );

    final downloadReleaseAarProgress = logger.progress(
      'Downloading release artifacts',
    );
    String releaseAarPath;
    try {
      releaseAarPath = await _downloadReleaseArtifact(
        Uri.parse(releaseAarArtifact.url),
        httpClient: _httpClient,
      );
    } catch (error) {
      downloadReleaseAarProgress.fail('$error');
      return ExitCode.software.code;
    }

    downloadReleaseAarProgress.complete();

    final aarDiffProgress =
        logger.progress('Checking for aar content differences');

    final contentDiffs = _aarDiffer.contentDifferences(
      releaseAarPath,
      aarArtifactPath(
        packageName: androidPackageName!,
        buildNumber: buildNumber,
      ),
    );

    aarDiffProgress.complete();

    if (contentDiffs.contains(ArchiveDifferences.assets)) {
      logger.info(
        yellow.wrap(
          '''⚠️ The Android Archive contains asset changes, which will not be included in the patch.''',
        ),
      );
      final shouldContinue = logger.confirm('Continue anyways?');
      if (!shouldContinue) {
        return ExitCode.success.code;
      }
    }

    final Map<Arch, String> releaseArtifactPaths;
    try {
      releaseArtifactPaths = await _downloadReleaseArtifacts(
        releaseArtifacts: releaseArtifacts,
        httpClient: _httpClient,
      );
    } catch (_) {
      return ExitCode.software.code;
    }

    final extractedAarDir = await extractAar(
      packageName: androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: _unzipFn,
    );

    final patchArtifactBundles = await _createPatchArtifacts(
      releaseArtifactPaths: releaseArtifactPaths,
      extractedAarDirectory: extractedAarDir,
    );
    if (patchArtifactBundles == null) {
      return ExitCode.software.code;
    }

    final archMetadata = patchArtifactBundles.keys.map((arch) {
      final name = arch.name;
      final size = formatBytes(patchArtifactBundles[arch]!.size);
      return '$name ($size)';
    });

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '📺 Channel: ${lightCyan.wrap(channelName)}',
      '''🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

    final needsConfirmation = !force;
    if (needsConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    await codePushClientWrapper.publishPatch(
      appId: appId,
      releaseId: release.id,
      platform: platformName,
      channelName: channelName,
      patchArtifactBundles: patchArtifactBundles,
    );

    logger.success('\n✅ Published Patch!');
    return ExitCode.success.code;
  }

  Future<Map<Arch, PatchArtifactBundle>?> _createPatchArtifacts({
    required Map<Arch, String> releaseArtifactPaths,
    required String extractedAarDirectory,
  }) async {
    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};

    final createDiffProgress = logger.progress('Creating artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final archMetadata = architectures[releaseArtifactPath.key]!;
      final artifactPath = p.join(
        extractedAarDirectory,
        'jni',
        archMetadata.path,
        'libapp.so',
      );
      logger.detail('Creating artifact for $artifactPath');
      final patchArtifact = File(artifactPath);
      final hash = _hashFn(await patchArtifact.readAsBytes());
      try {
        final diffPath = await createDiff(
          releaseArtifactPath: releaseArtifactPath.value,
          patchArtifactPath: artifactPath,
        );
        patchArtifactBundles[releaseArtifactPath.key] = PatchArtifactBundle(
          arch: archMetadata.arch,
          path: diffPath,
          hash: hash,
          size: await File(diffPath).length(),
        );
      } catch (error) {
        createDiffProgress.fail('$error');
        return null;
      }
    }
    createDiffProgress.complete();

    return patchArtifactBundles;
  }

  Future<String> _downloadReleaseArtifact(
    Uri uri, {
    required http.Client httpClient,
  }) async {
    final request = http.Request('GET', uri);
    final response = await httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        '''Failed to download release artifact: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp();
    final releaseArtifact = File(p.join(tempDir.path, 'artifact.so'));
    await releaseArtifact.openWrite().addStream(response.stream);

    return releaseArtifact.path;
  }

  Future<Map<Arch, String>> _downloadReleaseArtifacts({
    required Map<Arch, ReleaseArtifact> releaseArtifacts,
    required http.Client httpClient,
  }) async {
    final releaseArtifactPaths = <Arch, String>{};
    final downloadReleaseArtifactProgress = logger.progress(
      'Downloading release artifacts',
    );
    for (final releaseArtifact in releaseArtifacts.entries) {
      try {
        final releaseArtifactPath = await _downloadReleaseArtifact(
          Uri.parse(releaseArtifact.value.url),
          httpClient: httpClient,
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactPath;
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        rethrow;
      }
    }

    downloadReleaseArtifactProgress.complete();
    return releaseArtifactPaths;
  }
}
