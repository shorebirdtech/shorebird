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

/// Signature for a function that returns a [Patcher] for a given [ReleaseType].
typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

/// {@template patch_command}
/// A command that creates a shorebird patch for the provided target platforms.
/// `shorebird patch --platforms=android,ios`
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand {
  /// {@macro patch_command}
  PatchCommand({ResolvePatcher? resolvePatcher}) {
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
The version of the associated release (e.g. "1.0.0").
If you are building an xcframework or aar, this number needs to match the host app's release version.
To target the latest release (e.g. the release that was most recently updated) use --release-version=latest.''',
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
      ..addOption(
        'track',
        allowed: DeploymentTrack.values.map((v) => v.channel),
        help: 'The track to publish the patch to.',
        defaultsTo: DeploymentTrack.stable.channel,
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: '''
[DEPRECATED] Whether to publish the patch to the staging environment. Use --track=staging instead.''',
        hide: true,
      )
      ..addFlag(
        CommonArguments.noConfirmArg.name,
        help: CommonArguments.noConfirmArg.description,
        negatable: false,
      )
      ..addOption(
        CommonArguments.exportOptionsPlistArg.name,
        help: CommonArguments.exportOptionsPlistArg.description,
      )
      ..addOption(
        CommonArguments.exportMethodArg.name,
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
      )
      ..addOption(
        CommonArguments.minLinkPercentage.name,
        help: CommonArguments.minLinkPercentage.description,
        defaultsTo: CommonArguments.minLinkPercentage.defaultValue,
        allowed: [for (var i = 0; i <= 100; i++) '$i'],
      );
  }

  /// Warning message for when native code diffs are detected.
  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

  /// Warning message for when asset diffs are detected.
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

  /// Whether --no-confirm was passed.
  bool get noConfirm => results['no-confirm'] == true;

  /// Whether the patch is for the staging environment.
  bool get isStaging => track == DeploymentTrack.staging;

  /// Whether the patch is targeting the latest release version
  /// (--release-version=latest).
  bool get useLatestRelease => results['release-version'] == 'latest';

  /// The deployment track to publish the patch to.
  DeploymentTrack get track {
    final channel = results['track'] as String;
    return DeploymentTrack.values.firstWhere((t) => t.channel == channel);
  }

  @override
  Future<int> run() async {
    if (results.releaseTypes.isEmpty) {
      logger.err(
        '''No platforms were provided. Use the --platforms argument to provide one or more platforms''',
      );
      return ExitCode.usage.code;
    }

    if (results.wasParsed('staging')) {
      logger.err(
        '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
      );
      return ExitCode.usage.code;
    }

    final patcherFutures = results.releaseTypes
        .map(_resolvePatcher)
        .map(createPatch);

    for (final patcherFuture in patcherFutures) {
      await patcherFuture;
    }

    return ExitCode.success.code;
  }

  /// Returns a [Patcher] for the given [ReleaseType].
  @visibleForTesting
  Patcher getPatcher(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.aar:
        return AarPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
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
      case ReleaseType.linux:
        return LinuxPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.macos:
        return MacosPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.windows:
        return WindowsPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
    }
  }

  /// The last built Flutter revision.
  String? lastBuiltFlutterRevision;

  /// Creates a patch using the provided [patcher].
  @visibleForTesting
  Future<void> createPatch(Patcher patcher) async {
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();
    results.assertAbsentOrValidKeyPair();
    await shorebirdValidator.validateFlavors(flavorArg: flavor);

    await cache.updateAll();

    final app = await codePushClientWrapper.getApp(appId: appId);

    var inferredReleaseVersion = false;
    File? patchArtifactFile;
    final Release release;
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (useLatestRelease) {
      final releases = await codePushClientWrapper.getReleases(appId: appId);
      releases
        ..removeWhere(
          (release) => !release.platformStatuses.keys.contains(releasePlatform),
        )
        ..sortByUpdatedAt();
      if (releases.isEmpty) {
        logger.warn(
          '''No ${releasePlatform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
        );
        throw ProcessExit(ExitCode.usage.code);
      }
      // Use the most recently updated release for the specified platform.
      release = releases.last;
    } else if (results.wasParsed('release-version')) {
      final releaseVersion = results['release-version'] as String;
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } else if (shorebirdEnv.canAcceptUserInput) {
      release = await promptForRelease(releasePlatform);
    } else {
      final flutterVersionString =
          await shorebirdFlutter.getVersionAndRevision();
      logger.warn('''
The release version to patch was not specified.
Building with Flutter $flutterVersionString to determine the release version...
+-------------------------------------------------------------------------------+
| Specify a release version (e.g. --release-version=1.0.0+1)                    |
| to avoid a speculative build with the latest Flutter version.                 |
| Tip: Use --release-version=latest to target the highest release version.      |
+-------------------------------------------------------------------------------+
''');
      lastBuiltFlutterRevision = shorebirdEnv.flutterRevision;
      inferredReleaseVersion = true;
      patchArtifactFile = await patcher.buildPatchArtifact();
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
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: patcher.primaryReleaseArtifactArch,
      platform: releasePlatform,
    );

    final supplementalArtifact =
        patcher.supplementaryReleaseArtifactArch != null
            ? await codePushClientWrapper.maybeGetReleaseArtifact(
              appId: appId,
              releaseId: release.id,
              arch: patcher.supplementaryReleaseArtifactArch!,
              platform: releasePlatform,
            )
            : null;

    final releaseArchive = await downloadReleaseArtifact(
      releaseArtifact: releaseArtifact,
    );

    final supplementArchive =
        supplementalArtifact != null
            ? await downloadReleaseArtifact(
              releaseArtifact: supplementalArtifact,
            )
            : null;

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    return await runScoped(
      () async {
        await cache.updateAll();

        // Don't built the patch artifact twice with the same Flutter revision.
        if (lastBuiltFlutterRevision != release.flutterRevision) {
          final flutterVersionString =
              await shorebirdFlutter.getVersionAndRevision();
          logger.info('''
Building patch with Flutter $flutterVersionString
''');
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
          supplementArtifact: supplementArchive,
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
          inferredReleaseVersion: inferredReleaseVersion,
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
          track: track,
          artifacts: patchArtifactBundles,
        );
      },
      values: {shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv)},
    );
  }

  /// Prompts the user for the specific release to patch.
  Future<Release> promptForRelease(ReleasePlatform platform) async {
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final releasesForPlatform = releases.where(
      (release) => release.platformStatuses.keys.contains(platform),
    );

    if (releasesForPlatform.isEmpty) {
      logger.warn(
        '''No ${platform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    return logger.chooseOne<Release>(
      'Which release would you like to patch?',
      choices: [...releasesForPlatform.sortedBy((r) => r.createdAt).reversed],
      display: (r) => r.version,
    );
  }

  /// Asserts that the release contains a platform for the given [patcher].
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

  /// Asserts that the provided [release] is active.
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

  /// Ensures the diff between the release and patch archives is safe to patch.
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

  /// Confirms the patch creation (including a summary).
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
    final trackSummary =
        (() {
          return switch (track) {
            DeploymentTrack.staging => '🟠 Track: ${lightCyan.wrap('Staging')}',
            DeploymentTrack.beta => '🔵 Track: ${lightCyan.wrap('Beta')}',
            DeploymentTrack.stable => '🟢 Track: ${lightCyan.wrap('Stable')}',
          };
        })();

    final linkPercentage = patcher.linkPercentage;
    final minLinkPercentage = int.parse(
      results[CommonArguments.minLinkPercentage.name] as String,
    );
    if (linkPercentage != null && linkPercentage < minLinkPercentage) {
      logger.err(
        '''The link percentage of this patch ($linkPercentage%) is below the minimum threshold ($minLinkPercentage%). Exiting.''',
      );
      throw ProcessExit(ExitCode.software.code);
    }

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
      trackSummary,
      if (linkPercentage != null &&
          linkPercentage < Patcher.linkPercentageWarningThreshold)
        '''🔍 Debug Info: ${lightCyan.wrap(Patcher.debugInfoFile.path)}''',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''');

    if (shorebirdEnv.canAcceptUserInput && !noConfirm) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        throw ProcessExit(ExitCode.success.code);
      }
    }
  }

  /// Downloads the given [releaseArtifact].
  Future<File> downloadReleaseArtifact({
    required ReleaseArtifact releaseArtifact,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
        message: 'Downloading ${releaseArtifact.arch}',
      );
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactFile;
  }
}

/// Extension on list of releases for sorting the releases.
extension SortReleases on List<Release> {
  /// Sort the list of releases by when they were last updated ascending.
  void sortByUpdatedAt() => sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
}
