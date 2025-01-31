import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/iterable.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template patcher}
/// Platform-specific functionality to create a patch.
/// {@endtemplate}
abstract class Patcher {
  /// {@macro patcher}
  Patcher({
    required this.argParser,
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  /// Link percentage that is considered the minimum before a user might notice.
  static const double minLinkPercentage = 75;

  /// The standard link percentage warning.
  static String lowLinkPercentageWarning(double linkPercentage) {
    return '''
${lightCyan.wrap('shorebird patch')} was only able to share ${linkPercentage.toStringAsFixed(1)}% of Dart code with the released app.
This is unexpected, and means the application may execute slower than expected after patching.
Please reach out to us over Discord or Email for help.
More info: ${troubleshootingUrl.toLink()}.
''';
  }

  /// The parser for the arguments passed to the command.
  final ArgParser argParser;

  /// The arguments passed to the command.
  final ArgResults argResults;

  /// The flavor of the release, if any.
  final String? flavor;

  /// The target script to run, if any.
  final String? target;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The identifier used for the "primary" release artifact, usually a bundle.
  /// For example, 'aab' for Android, 'xcarchive' for iOS.
  String get primaryReleaseArtifactArch;

  /// The identifier used for any supplementary release artifacts.
  String? get supplementaryReleaseArtifactArch => null;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid() async {}

  /// Compares the release and patch artifacts to determine if the patch can be
  /// cleanly applied to the release.
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  });

  /// Builds the patch artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<File> buildPatchArtifact({String? releaseVersion});

  /// Determines the release version from the provided app artifact.
  Future<String> extractReleaseVersionFromArtifact(File artifact);

  /// Creates the patch artifacts required to apply a patch to a release.
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  });

  /// Updates the provided metadata to include patcher-specific fields.
  Future<CreatePatchMetadata> updatedCreatePatchMetadata(
    CreatePatchMetadata metadata,
  ) async {
    return metadata;
  }

  /// Uploads the patch artifacts to the CodePush server.
  Future<void> uploadPatchArtifacts({
    required String appId,
    required int releaseId,
    required Map<String, dynamic> metadata,
    required Map<Arch, PatchArtifactBundle> artifacts,
    required DeploymentTrack track,
  }) async {
    await codePushClientWrapper.publishPatch(
      appId: appId,
      releaseId: releaseId,
      metadata: metadata,
      platform: releaseType.releasePlatform,
      track: track,
      patchArtifactBundles: artifacts,
    );
  }

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => argResults['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => argResults['allow-native-diffs'] == true;

  /// The link percentage for the generated patch artifact if applicable.
  /// Returns `null` if the platform does not use a linker or if the linking
  /// step has not yet been run.
  double? get linkPercentage => null;

  /// The value of `--split-debug-info-path` if specified.
  String? get splitDebugInfoPath {
    return argResults.findOption(
      CommonArguments.splitDebugInfoArg.name,
      argParser: argParser,
    );
  }

  /// The build directory of the respective shorebird project.
  Directory get buildDirectory {
    return Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'build'),
    );
  }

  /// The path to the output file for the debug info.
  File get debugInfoFile {
    return File(p.join(buildDirectory.path, 'patch-debug.zip'));
  }

  /// Extracts the --build-name and --build-number from the --release-version
  /// argument if it's provided. Given `--release-version=1.2.3+4`, this will
  /// return `['--build-name=1.2.3', '--build-number=4']`, with the intent that
  /// these values will be forwarded to the `flutter build` command.
  ///
  /// Because not all platform types support both --build-name and
  /// --build-number, this needs to be handled in the platform-specific
  /// patchers instead of at the patch command level.
  ///
  /// We do this because some platforms encode the build version in their
  /// binaries (Android does this with .dex files). If a release and a patch
  /// have different version numbers, our [PatchDiffChecker] to warn the user of
  /// native changes, even though the user may not have actually changed any
  /// code or dependencies.
  ///
  /// Context: https://github.com/shorebirdtech/shorebird/issues/2270
  List<String> buildNameAndNumberArgsFromReleaseVersion(
    String? releaseVersion,
  ) {
    if (releaseVersion == null || !releaseVersion.contains('+')) {
      return [];
    }

    // If the user provided --build-name or --build-number before the --, we
    // don't want to override them.
    if (argResults.options.containsAnyOf([
      CommonArguments.buildNameArg.name,
      CommonArguments.buildNumberArg.name,
    ])) {
      return [];
    }

    // If the user provided --build-name or --build-number after the --, we
    // don't want to override them.
    if (argResults.rest.any(
      (a) =>
          a.startsWith('--${CommonArguments.buildNameArg.name}') ||
          a.startsWith('--${CommonArguments.buildNumberArg.name}'),
    )) {
      return [];
    }

    final parts = releaseVersion.split('+');
    return [
      '--build-name=${parts[0]}',
      '--build-number=${parts[1]}',
    ];
  }
}
