import 'dart:io';

import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

abstract class Patcher {
  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  ArchiveDiffer get archiveDiffer;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid();

  Future<String> getReleaseVersion();

  Future<Release> getRelease();

  Future<File> getReleaseArtifact();

  Future<void> assertReleaseIsPatchable();

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<File> buildPatchArtifacts();

  /// Uploads the release artifacts to the CodePush server.
  Future<void> uploadPatchArtifacts({
    required Release release,
    required String appId,
  });

  /// Metadata to attach to the release when creating it, used for debugging
  /// and support.
  Future<CreatePatchMetadata> patchMetadata();

  /// Instructions explaining next steps after running `shorebird release`. This
  /// could include how to upload the generated artifact to a store and how to
  /// patch the release.
  String get postReleaseInstructions;
}
