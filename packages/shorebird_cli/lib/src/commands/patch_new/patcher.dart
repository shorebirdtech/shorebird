import 'dart:io';

import 'package:args/args.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

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
  });
}
