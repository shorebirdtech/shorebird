import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

class PatchCommand extends ShorebirdCommand {
  PatchCommand({
    ResolvePatcher? resolvePatcher,
  }) {
    _resolvePatcher = resolvePatcher ?? getPatcher;
    argParser
      ..addMultiOption(
        'platforms',
        abbr: 'p',
        help: 'The platform(s) to to build this release for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
        // TODO(bryanoltman): uncomment this once https://github.com/dart-lang/args/pull/273 lands
        // mandatory: true.
      )
      ..addOption(
        'build-number',
        help: '''
An identifier used as an internal version number.
Each build must have a unique identifier to differentiate it from previous builds.
It is used to determine whether one build is more recent than another, with higher numbers indicating more recent build.
On Android it is used as "versionCode".
On Xcode builds it is used as "CFBundleVersion".''',
        defaultsTo: '1.0',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
      )
      ..addFlag(
        'allow-native-diffs',
        help: allowNativeDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'allow-asset-diffs',
        help: allowAssetDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: 'Whether to publish the patch to the staging environment.',
      )
      ..addOption(
        exportOptionsPlistArgName,
        help:
            '''Export an IPA with these options. See "xcodebuild -h" for available exportOptionsPlist keys (iOS only).''',
      )
      ..addFlag(
        'codesign',
        help: 'Codesign the application bundle (iOS only).',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      )
      ..addOption(
        'private-key-path',
        hide: true,
        help: '''
The path for a private key file that will be used to sign the patch artifact.
''',
      );
  }

  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

  static final allowAssetDiffsHelpText = '''
Patch even if asset diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Asset changes cannot be included in a patch can cause your app to behave unexpectedly.''';

  late final ResolvePatcher _resolvePatcher;

  @override
  String get description =>
      'Creates a shorebird patch for the provided target platforms';

  @override
  String get name => 'patch';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late String? target = results.findOption('target', argParser: argParser);

  bool get isStaging => results['staging'] == true;

  @override
  Future<int> run() async {
    final patcherFutures =
        results.releaseTypes.map(_resolvePatcher).map(createPatch);

    for (final patcherFuture in patcherFutures) {
      await patcherFuture;
    }

    return ExitCode.success.code;
  }

  @visibleForTesting
  Patcher getPatcher(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.android:
        return AndroidPatcher(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        return IosPatcher(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.iosFramework:
        return IosFrameworkPatcher(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.aar:
        return AarPatcher(
          argResults: results,
          flavor: flavor,
          target: target,
        );
    }
  }

  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

  String? lastBuiltFlutterRevision;

  @visibleForTesting
  Future<void> createPatch(Patcher patcher) async {
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();

    await cache.updateAll();

    final app = await codePushClientWrapper.getApp(appId: appId);

    File? patchArtifact;
    final Release release;
    if (results.wasParsed('release-version')) {
      final releaseVersion = results['release-version'] as String;
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } else if (shorebirdEnv.canAcceptUserInput) {
      release = await promptForRelease();
    } else {
      logger.info(
        '''Tip: make your patches build faster by specifying --release-version''',
      );
      patchArtifact = await patcher.buildPatchArtifact();
      lastBuiltFlutterRevision = shorebirdEnv.flutterRevision;
      final releaseVersion = await patcher.extractReleaseVersionFromArtifact(
        patchArtifact,
      );
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    }

    assertReleaseIsActive(release: release, patcher: patcher);

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } catch (_) {
      exit(ExitCode.software.code);
    }

    final releaseArtifact = await downloadPrimaryReleaseArtifact(
      release: release,
      patcher: patcher,
    );

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    return await runScoped(
      () async {
        await cache.updateAll();

        // Don't built the patch artifact twice with the same Flutter revision.
        if (lastBuiltFlutterRevision != release.flutterRevision) {
          patchArtifact = await patcher.buildPatchArtifact();
        }

        final diffStatus = await assertUnpatchableDiffs(
          releaseArtifact: releaseArtifact,
          patchArtifact: patchArtifact!,
          archiveDiffer: patcher.archiveDiffer,
        );
        final patchArtifactBundles = await patcher.createPatchArtifacts(
          appId: appId,
          releaseId: release.id,
          releaseArtifact: releaseArtifact,
        );

        final dryRun = results['dry-run'] == true;
        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          exit(ExitCode.success.code);
        }

        await confirmCreatePatch(
          app: app,
          releaseVersion: release.version,
          patcher: patcher,
          patchArtifactBundles: patchArtifactBundles,
        );
        await codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
          metadata: await patcher.createPatchMetadata(diffStatus),
          platform: patcher.releaseType.releasePlatform,
          track:
              isStaging ? DeploymentTrack.staging : DeploymentTrack.production,
          patchArtifactBundles: patchArtifactBundles,
        );
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }

  Future<Release> promptForRelease() async {
    final releases = await codePushClientWrapper.getReleases(
      appId: appId,
    );
    return logger.chooseOne<Release>(
      'Which release would you like to patch?',
      choices: releases.sortedBy((r) => r.createdAt).reversed.toList(),
      display: (r) => r.version,
    );
  }

  void assertReleaseIsActive({
    required Release release,
    required Patcher patcher,
  }) {
    final releaseStatus =
        release.platformStatuses[patcher.releaseType.releasePlatform];
    if (releaseStatus != ReleaseStatus.active) {
      logger.err('''
Release ${release.version} is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.''');
      exit(ExitCode.software.code);
    }
  }

  Future<DiffStatus> assertUnpatchableDiffs({
    required File releaseArtifact,
    required File patchArtifact,
    required ArchiveDiffer archiveDiffer,
  }) async {
    try {
      return await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
        localArtifact: patchArtifact,
        releaseArtifact: releaseArtifact,
        archiveDiffer: archiveDiffer,
        allowAssetChanges: allowAssetDiffs,
        allowNativeChanges: allowNativeDiffs,
      );
    } on UserCancelledException {
      exit(ExitCode.success.code);
    } on UnpatchableChangeException {
      logger.info('Exiting.');
      exit(ExitCode.software.code);
    }
  }

  Future<void> confirmCreatePatch({
    required AppMetadata app,
    required String releaseVersion,
    required Patcher patcher,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final archMetadata = patchArtifactBundles.keys.map((arch) {
      final size = formatBytes(patchArtifactBundles[arch]!.size);
      return '${arch.name} ($size)';
    });
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.name)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
      if (isStaging)
        '🟠 Track: ${lightCyan.wrap('Staging')}'
      else
        '🟢 Track: ${lightCyan.wrap('Production')}',
      if (patcher.linkPercentage != null)
        '''🔗 Running ${lightCyan.wrap('${patcher.linkPercentage!.toStringAsFixed(1)}%')} on CPU''',
      if (patcher.linkPercentage != null &&
          patcher.linkPercentage! < Patcher.minLinkPercentage)
        '''🔍 Debug Info: ${lightCyan.wrap(patcher.debugInfoFile.path)}''',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

    if (shorebirdEnv.canAcceptUserInput) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        exit(ExitCode.success.code);
      }
    }
  }

  Future<File> downloadPrimaryReleaseArtifact({
    required Release release,
    required Patcher patcher,
  }) async {
    final artifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: patcher.primaryReleaseArtifactArch,
      platform: patcher.releaseType.releasePlatform,
    );

    final downloadProgress =
        logger.progress('Downloading ${patcher.primaryReleaseArtifactArch}');
    final File artifactFile;
    try {
      artifactFile =
          await artifactManager.downloadFile(Uri.parse(artifact.url));
    } catch (e) {
      downloadProgress.fail(e.toString());
      exit(ExitCode.software.code);
    }

    downloadProgress.complete();
    return artifactFile;
  }
}
