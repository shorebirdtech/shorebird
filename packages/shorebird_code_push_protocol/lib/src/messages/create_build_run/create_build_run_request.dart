import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/build_run_build_flags.dart';
import 'package:shorebird_code_push_protocol/src/models/build_run_command.dart';
import 'package:shorebird_code_push_protocol/src/models/build_run_failure_reason.dart';
import 'package:shorebird_code_push_protocol/src/models/build_run_outcome.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template create_build_run_request}
/// The request body for POST /apps/{appId}/runs.
/// {@endtemplate}
@immutable
class CreateBuildRunRequest {
  /// {@macro create_build_run_request}
  const CreateBuildRunRequest({
    required this.runId,
    required this.command,
    required this.platform,
    required this.outcome,
    required this.startedAt,
    required this.durationMs,
    required this.dryRun,
    this.reason,
    this.releaseId,
    this.patchId,
    this.metadata,
    this.buildFlags,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateBuildRunRequest].
  factory CreateBuildRunRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateBuildRunRequest',
      json,
      () => CreateBuildRunRequest(
        runId: json['run_id'] as String,
        command: BuildRunCommand.fromJson(json['command'] as String),
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        outcome: BuildRunOutcome.fromJson(json['outcome'] as String),
        reason: BuildRunFailureReason.maybeFromJson(json['reason'] as String?),
        releaseId: json['release_id'] as int?,
        patchId: json['patch_id'] as int?,
        startedAt: DateTime.parse(json['started_at'] as String),
        durationMs: json['duration_ms'] as int,
        dryRun: json['dry_run'] as bool,
        metadata: json['metadata'] as Map<String, dynamic>?,
        buildFlags: BuildRunBuildFlags.maybeFromJson(
          json['build_flags'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateBuildRunRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateBuildRunRequest.fromJson(json);
  }

  /// Chosen by the CLI for each command it runs. Shared by the
  /// records of one run's platforms.
  final String runId;

  /// The CLI command a build run recorded.
  final BuildRunCommand command;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// How a build run ended.
  final BuildRunOutcome outcome;

  /// Why a build run failed.
  final BuildRunFailureReason? reason;

  /// The release the run made or patched, if it got one.
  final int? releaseId;

  /// The patch the run made, if it made one.
  final int? patchId;

  /// When the platform's work began.
  final DateTime startedAt;

  /// How long the platform's work took, in milliseconds.
  final int durationMs;

  /// Whether the run was a --dry-run.
  final bool dryRun;

  /// The metadata the CLI sends with a published release or patch,
  /// including its build trace summary, as far as the run got.
  final Map<String, dynamic>? metadata;

  /// The flags a run built with that change compiled Dart code, as
  /// SHA-256 hashes. Never holds dart-define values or paths.
  final BuildRunBuildFlags? buildFlags;

  /// Converts a [CreateBuildRunRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'run_id': runId,
      'command': command.toJson(),
      'platform': platform.toJson(),
      'outcome': outcome.toJson(),
      'reason': ?reason?.toJson(),
      'release_id': ?releaseId,
      'patch_id': ?patchId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_ms': durationMs,
      'dry_run': dryRun,
      'metadata': ?metadata,
      'build_flags': ?buildFlags?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    runId,
    command,
    platform,
    outcome,
    reason,
    releaseId,
    patchId,
    startedAt,
    durationMs,
    dryRun,
    mapHash(metadata),
    buildFlags,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateBuildRunRequest &&
        runId == other.runId &&
        command == other.command &&
        platform == other.platform &&
        outcome == other.outcome &&
        reason == other.reason &&
        releaseId == other.releaseId &&
        patchId == other.patchId &&
        startedAt == other.startedAt &&
        durationMs == other.durationMs &&
        dryRun == other.dryRun &&
        mapsEqual(metadata, other.metadata) &&
        buildFlags == other.buildFlags;
  }
}
