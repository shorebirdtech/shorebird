import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/patch_new/android_patcher.dart';
import 'package:shorebird_cli/src/commands/patch_new/patcher.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

class PatchNewCommand extends ShorebirdCommand {
  PatchNewCommand({
    ResolvePatcher? resolvePatcher,
  }) {
    _resolvePatcher = resolvePatcher ?? getPatcher;
    argParser
      ..addMultiOption(
        'platform',
        abbr: 'p',
        help: 'The platform(s) to to build this release for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
        // TODO(bryanoltman): uncomment this once https://github.com/dart-lang/args/pull/273 lands
        // mandatory: true.
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
  bool get hidden => true;

  @override
  String get description =>
      'Creates a shorebird patch for the provided target platforms';

  @override
  String get name => 'patch-new';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late String? target = results.findOption('target', argParser: argParser);

  bool get isStaging => results['staging'] == true;

  @override
  Future<int> run() async {
    final patcherFutures = (results['platform'] as List<String>)
        .map(
          (platformArg) => ReleaseType.values.firstWhere(
            (target) => target.cliName == platformArg,
          ),
        )
        .map(_resolvePatcher)
        .map(createPatch);

    await Future.wait(patcherFutures);
    return ExitCode.success.code;
  }

  @visibleForTesting
  Patcher getPatcher(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.android:
        return AndroidPatcher();
      case ReleaseType.ios:
        throw UnimplementedError();
      case ReleaseType.iosFramework:
        throw UnimplementedError();
      case ReleaseType.aar:
        throw UnimplementedError();
    }
  }

  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

  @visibleForTesting
  Future<void> createPatch(Patcher patcher) async {
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();

    final releaseVersion = await patcher.getReleaseVersion();
    final release = await patcher.getRelease();
    final releaseArtifact = await patcher.getReleaseArtifact();

    await patcher.assertReleaseIsPatchable();

    // This command handles logging, we don't need to provide our own
    // progress, error logs, etc.
    final app = await codePushClientWrapper.getApp(appId: appId);

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } catch (_) {
      exit(ExitCode.software.code);
    }

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};

    final patchArtifact = await patcher.buildPatchArtifacts();

    await assertUnpatchableDiffs(
      releaseArtifact: releaseArtifact,
      patchArtifact: patchArtifact,
      archiveDiffer: patcher.archiveDiffer,
    );

    return await runScoped(
      () async {
        await codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
          metadata: await patcher.patchMetadata(),
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

  Future<DiffStatus> assertUnpatchableDiffs({
    required File releaseArtifact,
    required File patchArtifact,
    required ArchiveDiffer archiveDiffer,
  }) async {
    try {
      return patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
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
}
