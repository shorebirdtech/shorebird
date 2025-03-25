import 'dart:io';

import 'package:args/args.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template releaser}
/// Executes platform-specific functionality to create a release.
/// {@endtemplate}
abstract class Releaser {
  /// {@macro releaser}
  Releaser({
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  /// The arguments passed to the command.
  final ArgResults argResults;

  /// The flavor of the release, if any. This is the --flavor argument passed to
  /// the release command.
  final String? flavor;

  /// The target script to run, if any. This is the --target argument passed to
  /// the release command.
  final String? target;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// The human-readable description of the release artifact being built (e.g.,
  /// "Android app", "iOS app").
  String get artifactDisplayName;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid();

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<FileSystemEntity> buildReleaseArtifacts();

  /// Uploads the release artifacts to the CodePush server.
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  });

  /// Creates a copy of [metadata] with releaser-specific fields updated.
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async {
    return metadata;
  }

  /// Instructions explaining next steps after running `shorebird release`. This
  /// could include how to upload the generated artifact to a store and how to
  /// patch the release.
  String get postReleaseInstructions;

  /// Extracts the release version from the compiled artifact.
  ///
  /// We extract the release version from the compiled artifact because we can
  /// be 100% certain that the artifact will report that same number when making
  /// patch check requests.
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  });
}
