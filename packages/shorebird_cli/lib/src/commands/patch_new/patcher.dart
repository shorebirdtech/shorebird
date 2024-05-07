import 'dart:io';

import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// {@template patcher}
/// Platform-specific functionality to create a patch.
/// {@endtemplate}
abstract class Patcher {
  /// {@macro patcher}
  Patcher({required this.flavor, required this.target});

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
  Future<void> assertArgsAreValid();

  /// Get the release version. Builds the app to determine
  Future<String> buildAppAndGetReleaseVersion();

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<File> buildPatchArtifact({
    required String? flavor,
    required String? target,
  });

  /// The artifact to compare against the release to determine whether the patch
  /// contains unpatchable changes.
  Future<File> patchArtifactForDiffCheck();

  /// Creates the patch artifacts required to apply a patch to a release.
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
  });
}
