import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';
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

  /// Whether --release-version must be specified to release. Currently only
  /// required for add-to-app/hybrid releases (aar and ios-framework).
  bool get requiresReleaseVersionArg => false;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

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

  /// Metadata to attach to the release when creating it, used for debugging
  /// and support.
  Future<UpdateReleaseMetadata> releaseMetadata();

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

  /// Method for validating a public key argument, which will check, when
  /// provided, that the file exists.
  ///
  /// This method should be called in [assertArgsAreValid] from releasers that
  /// require a public key argument.
  void assertPublicKeyArg() {
    final patchSignKeyPath = argResults['public-key-path'] as String?;
    if (patchSignKeyPath != null) {
      final file = File(patchSignKeyPath);
      if (!file.existsSync()) {
        logger.err(
          'No file found at $patchSignKeyPath',
        );
        exit(ExitCode.software.code);
      }
    }
  }
}
