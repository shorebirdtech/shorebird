import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patcher}
/// Platform-specific functionality to create a patch.
/// {@endtemplate}
abstract class Patcher {
  /// {@macro patcher}
  Patcher({
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  // Link percentage that is considered the minimum before a user might notice.
  // Our early testing has shown that about:
  // - 1/3rd of patches link at 99%
  // - 1/3rd of patches link between 20% and 99%
  // - 1/3rd of patches link below 20%
  // Most lowering is likely due to:
  // https://github.com/shorebirdtech/shorebird/issues/1825
  static const double minLinkPercentage = 75;

  /// The standard link percentage warning.
  static String lowLinkPercentageWarning(double linkPercentage) {
    return '''
${lightCyan.wrap('shorebird patch')} was only able to share ${linkPercentage.toStringAsFixed(1)}% of Dart code with the released app.
This means the patched code may execute slower than expected.
https://docs.shorebird.dev/status#link-percentage-ios
''';
  }

  /// The arguments passed to the command.
  final ArgResults argResults;

  /// The flavor of the release, if any.
  final String? flavor;

  /// The target script to run, if any.
  final String? target;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// Used to compare release and patch artifacts to determine if a patch can
  /// be applied to a release.
  ArchiveDiffer get archiveDiffer;

  /// The identifier used for the "primary" release artifact, usually a bundle.
  /// For example, 'aab' for Android, 'xcarchive' for iOS.
  String get primaryReleaseArtifactArch;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid() async {}

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<File> buildPatchArtifact();

  /// Determines the release version from the provided app artifact.
  Future<String> extractReleaseVersionFromArtifact(File artifact);

  /// Creates the patch artifacts required to apply a patch to a release.
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  });

  /// Metadata to attach to the patch when creating it, used for debugging
  /// and support.
  Future<CreatePatchMetadata> createPatchMetadata(DiffStatus diffStatus);

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => argResults['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => argResults['allow-native-diffs'] == true;

  /// The link percentage for the generated patch artifact if applicable.
  /// Returns `null` if the platform does not use a linker or if the linking
  /// step has not yet been run.
  double? get linkPercentage => null;

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
}
