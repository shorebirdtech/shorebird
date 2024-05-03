import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template build_pipeline_exception}
/// An recoverable exception that occurs during the build pipeline. Will cause
/// the command to exit early with [exitCode] after logging [message] to the
/// console.
/// {@endtemplate}
class ReleaserException implements Exception {
  /// {@macro build_pipeline_exception}
  ReleaserException({
    required this.exitCode,
    required this.message,
  });

  /// The exit code to use when exiting the command.
  final ExitCode exitCode;

  /// The message to log to the console, if any.
  final String? message;

  @override
  String toString() =>
      'BuildPipelineException: $message (exit code: $exitCode)';
}

/// {@template release_pipeline}
/// A workflow to create a new release for a Shorebird app.
/// {@endtemplate}
abstract class Releaser {
  /// {@macro release_pipeline}
  Releaser({
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  /// The arguments passed to the command.
  final ArgResults argResults;

  final String? flavor;
  final String? target;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// Asserts that the command can be run.
  Future<void> validatePreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> validateArgs();

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
  UpdateReleaseMetadata get releaseMetadata;

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
