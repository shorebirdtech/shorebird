// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

class PatchCommand extends ShorebirdCommand {
  PatchCommand({
    ResolvePatcher? resolvePatcher,
  }) {
    _resolvePatcher = resolvePatcher ?? getPatcher;
    argParser
      ..addMultiOption(
        CommonArguments.dartDefineArg.name,
        help: CommonArguments.dartDefineArg.description,
      )
      ..addMultiOption(
        CommonArguments.dartDefineFromFileArg.name,
        help: CommonArguments.dartDefineFromFileArg.description,
      )
      ..addMultiOption(
        'platforms',
        abbr: 'p',
        help: 'The platform(s) to to build this release for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
      )
      ..addOption(
        CommonArguments.buildNameArg.name,
        help: CommonArguments.buildNameArg.description,
        defaultsTo: CommonArguments.buildNameArg.defaultValue,
      )
      ..addOption(
        CommonArguments.buildNumberArg.name,
        help: CommonArguments.buildNumberArg.description,
        defaultsTo: CommonArguments.buildNumberArg.defaultValue,
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
        CommonArguments.exportOptionsPlistArg.name,
        help: CommonArguments.exportOptionsPlistArg.description,
      )
      ..addOption(
        CommonArguments.exportMethodArg.name,
        defaultsTo: ExportMethod.appStore.argName,
        allowed: ExportMethod.values.map((e) => e.argName),
        help: CommonArguments.exportMethodArg.description,
        allowedHelp: {
          for (final method in ExportMethod.values)
            method.argName: method.description,
        },
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
        CommonArguments.privateKeyArg.name,
        help: CommonArguments.privateKeyArg.description,
      )
      ..addOption(
        CommonArguments.publicKeyArg.name,
        help: CommonArguments.publicKeyArg.description,
      )
      ..addOption(
        CommonArguments.splitDebugInfoArg.name,
        help: CommonArguments.splitDebugInfoArg.description,
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

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

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
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        return IosPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.iosFramework:
        return IosFrameworkPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.aar:
        return AarPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
    }
  }

  String? lastBuiltFlutterRevision;

  @visibleForTesting
  Future<void> createPatch(Patcher patcher) async {
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();
    results.assertAbsentOrValidKeyPair();
    await shorebirdValidator.validateFlavors(flavorArg: flavor);

    await cache.updateAll();

    final app = await codePushClientWrapper.getApp(appId: appId);

    File? patchArtifactFile;
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
      patchArtifactFile = await patcher.buildPatchArtifact();
      lastBuiltFlutterRevision = shorebirdEnv.flutterRevision;
      final releaseVersion = await patcher.extractReleaseVersionFromArtifact(
        patchArtifactFile,
      );
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    }

    assertReleaseContainsPlatform(release: release, patcher: patcher);
    assertReleaseIsActive(release: release, patcher: patcher);

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: patcher.primaryReleaseArtifactArch,
      platform: patcher.releaseType.releasePlatform,
    );

    final releaseArchive = await downloadPrimaryReleaseArtifact(
      releaseArtifact: releaseArtifact,
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
          patchArtifactFile = await patcher.buildPatchArtifact(
            releaseVersion: release.version,
          );
        }

        final diffStatus = await assertUnpatchableDiffs(
          releaseArtifact: releaseArtifact,
          releaseArchive: releaseArchive,
          patchArchive: patchArtifactFile!,
          patcher: patcher,
        );
        final patchArtifactBundles = await patcher.createPatchArtifacts(
          appId: appId,
          releaseId: release.id,
          releaseArtifact: releaseArchive,
        );

        final dryRun = results['dry-run'] == true;
        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          throw ProcessExit(ExitCode.success.code);
        }

        await confirmCreatePatch(
          app: app,
          releaseVersion: release.version,
          patcher: patcher,
          patchArtifactBundles: patchArtifactBundles,
        );

        final baseMetadata = CreatePatchMetadata(
          releasePlatform: patcher.releaseType.releasePlatform,
          usedIgnoreAssetChangesFlag: allowAssetDiffs,
          hasAssetChanges: diffStatus.hasAssetChanges,
          usedIgnoreNativeChangesFlag: allowNativeDiffs,
          hasNativeChanges: diffStatus.hasNativeChanges,
          environment: BuildEnvironmentMetadata(
            flutterRevision: shorebirdEnv.flutterRevision,
            operatingSystem: platform.operatingSystem,
            operatingSystemVersion: platform.operatingSystemVersion,
            shorebirdVersion: packageVersion,
            shorebirdYaml: shorebirdEnv.getShorebirdYaml()!,
          ),
        );
        final updateMetadata = await patcher.updatedCreatePatchMetadata(
          baseMetadata,
        );

        await patcher.uploadPatchArtifacts(
          appId: appId,
          releaseId: release.id,
          metadata: updateMetadata.toJson(),
          track:
              isStaging ? DeploymentTrack.staging : DeploymentTrack.production,
          artifacts: patchArtifactBundles,
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

    if (releases.isEmpty) {
      logger.warn(
        '''No releases found for app $appId. You need to make first a release before you can create a patch.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    return logger.chooseOne<Release>(
      'Which release would you like to patch?',
      choices: releases.sortedBy((r) => r.createdAt).reversed.toList(),
      display: (r) => r.version,
    );
  }

  void assertReleaseContainsPlatform({
    required Release release,
    required Patcher patcher,
  }) {
    final releasePlatform = patcher.releaseType.releasePlatform;
    final contains = release.platformStatuses.containsKey(releasePlatform);
    if (!contains) {
      final platformName = releasePlatform.name;
      logger.err(
        '''No release exists for $platformName in release version ${release.version}. Please run shorebird release $platformName to create one.''',
      );
      throw ProcessExit(ExitCode.software.code);
    }
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
      throw ProcessExit(ExitCode.software.code);
    }
  }

  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File patchArchive,
    required File releaseArchive,
    required Patcher patcher,
  }) async {
    try {
      return patcher.assertUnpatchableDiffs(
        releaseArtifact: releaseArtifact,
        releaseArchive: releaseArchive,
        patchArchive: patchArchive,
      );
    } on UserCancelledException {
      throw ProcessExit(ExitCode.success.code);
    } on UnpatchableChangeException {
      logger.info('Exiting.');
      throw ProcessExit(ExitCode.software.code);
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
        throw ProcessExit(ExitCode.success.code);
      }
    }
  }

  Future<File> downloadPrimaryReleaseArtifact({
    required ReleaseArtifact releaseArtifact,
    required Patcher patcher,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
        message: 'Downloading ${patcher.primaryReleaseArtifactArch}',
      );
    } catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactFile;
  }
}
