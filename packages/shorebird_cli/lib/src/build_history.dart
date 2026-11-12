import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/build_flags.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:uuid/uuid.dart';

/// A reference to a [BuildHistory] instance.
final buildHistoryRef = create(BuildHistory.new);

/// The [BuildHistory] instance available in the current zone.
BuildHistory get buildHistory => read(buildHistoryRef);

/// {@template build_run}
/// One platform's part of a `shorebird release` or `shorebird patch` run,
/// filled in by the command as it goes and sent to the app's build history
/// when it ends.
/// {@endtemplate}
class BuildRun {
  /// {@macro build_run}
  BuildRun({
    required this.runId,
    required this.command,
    required this.platform,
    required this.dryRun,
    required this.startedAt,
  });

  /// Shared by the records of one command's platforms.
  final String runId;

  /// The command that ran.
  final BuildRunCommand command;

  /// The platform this record covers.
  final ReleasePlatform platform;

  /// Whether the run was a `--dry-run`.
  final bool dryRun;

  /// When this platform's work began.
  final DateTime startedAt;

  /// The app the run is filed under, set once the server has confirmed it.
  /// A run that stops before then is not recorded: there is no app to file
  /// it under.
  String? appId;

  /// The release the run made or patched, once it has one.
  int? releaseId;

  /// The patch the run made, once it has one.
  int? patchId;

  /// The metadata the command sent with its release or patch, set when it
  /// got that far.
  Json? metadata;

  /// The run's dart-define and target hashes.
  BuildRunBuildFlags? buildFlags;

  /// Why the run failed, set where the command stops. A failure with none is
  /// classified by its exit (see [BuildHistory.record]).
  BuildRunFailureReason? get reason => _reason;
  BuildRunFailureReason? _reason;

  /// Sets [reason] unless one is already set: the first stop is the cause.
  void failWith(BuildRunFailureReason reason) => _reason ??= reason;

  /// Whether the person running the command asked to share this run's debug
  /// bundle (`shorebird patch --share-debug-info`), whatever the
  /// organization's setting.
  bool shareDebugInfo = false;

  File? _debugBundle;
  DateTime? _debugBundleModifiedAtStart;

  /// Offers [file], where the run writes its debug bundle, to the server with
  /// the record, if the run writes it. A file a previous run left there and
  /// this run didn't rewrite is never offered.
  void watchDebugBundle(File file) {
    _debugBundle = file;
    _debugBundleModifiedAtStart = file.existsSync()
        ? file.lastModifiedSync()
        : null;
  }

  /// The debug bundle this run wrote, or null if it wrote none.
  File? get writtenDebugBundle {
    final file = _debugBundle;
    if (file == null || !file.existsSync()) return null;
    if (file.lastModifiedSync() == _debugBundleModifiedAtStart) return null;
    return file;
  }
}

/// Runs [body], blaming a failure on [reason] in [run], if there is one,
/// unless the Shorebird API refused a request ([ApiErrorExit]) or the user
/// declined a prompt ([PromptDeclinedExit]): those keep their own reasons.
Future<T> blameFailureOn<T>(
  BuildRun? run,
  BuildRunFailureReason reason,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on ProcessExit catch (exit) {
    if (exit.exitCode != ExitCode.success.code &&
        exit is! ApiErrorExit &&
        exit is! PromptDeclinedExit) {
      run?.failWith(reason);
    }
    rethrow;
  }
}

/// {@template build_history}
/// Records each `shorebird release` and `shorebird patch` run in the app's
/// build history on the server, one record per platform: whether it
/// succeeded or why it failed, how long it took, and the metadata and build
/// flag hashes the command sends with a release or patch. Never logs, error
/// messages, paths or dart-define values.
///
/// A patch run that wrote a debug bundle (`build/patch-debug.zip`) says so,
/// with its size. When the server answers with an upload for it (the
/// organization shares debug info, or the run passed `--share-debug-info`),
/// the bundle is uploaded to Shorebird.
///
/// Sending is best effort: a failed send never changes the run's result.
/// Crashes of the CLI and Ctrl-C aren't recorded.
/// {@endtemplate}
class BuildHistory {
  /// {@macro build_history}
  BuildHistory({String? runId}) : runId = runId ?? const Uuid().v4();

  /// Shared by every record this process sends.
  final String runId;

  /// How long sending a record may take before it is dropped.
  @visibleForTesting
  static const sendTimeout = Duration(seconds: 5);

  /// Starts the record of [platform]'s part of [command].
  ///
  /// Clears the build trace a previous platform left, so this platform's
  /// record never carries another's timings.
  BuildRun start({
    required BuildRunCommand command,
    required ReleasePlatform platform,
    required bool dryRun,
  }) {
    buildTraceSession
      ..traceFile = null
      ..platform = null
      ..summary = null;
    return BuildRun(
      runId: runId,
      command: command,
      platform: platform,
      dryRun: dryRun,
      startedAt: clock.now(),
    );
  }

  /// Runs [body], the work of [run], and sends [run]'s record when it ends.
  ///
  /// A [ProcessExit] with code 0 (a dry run that found no issues) is a
  /// success; any other [ProcessExit] or a [UsageException] is a failure.
  /// Its reason is [BuildRun.reason] if the command set one, otherwise
  /// [BuildRunFailureReason.serverRejected] for an [ApiErrorExit],
  /// [BuildRunFailureReason.canceled] for a [PromptDeclinedExit], and
  /// [BuildRunFailureReason.other] for the rest.
  /// Anything else is a crash and isn't recorded.
  ///
  /// When the run ends without [BuildRun.metadata], [metadata] is asked for
  /// what the run got as far as. A [metadata] that fails sends none.
  Future<T> record<T>(
    BuildRun run,
    Future<T> Function() body, {
    required Future<Json> Function() metadata,
  }) async {
    final T result;
    try {
      result = await body();
    } on ProcessExit catch (exit) {
      if (exit.exitCode == ExitCode.success.code) {
        await _send(
          run,
          outcome: BuildRunOutcome.succeeded,
          metadata: metadata,
        );
      } else {
        await _send(
          run,
          outcome: BuildRunOutcome.failed,
          reason: run.reason ?? _reasonFor(exit),
          metadata: metadata,
        );
      }
      rethrow;
    } on UsageException {
      await _send(
        run,
        outcome: BuildRunOutcome.failed,
        reason: run.reason ?? BuildRunFailureReason.other,
        metadata: metadata,
      );
      rethrow;
    }
    await _send(run, outcome: BuildRunOutcome.succeeded, metadata: metadata);
    return result;
  }

  /// The hashes of the dart-defines and target in [results], or null if they
  /// can't be read, such as a `--dart-define-from-file` that is missing (the
  /// build reports that, not the record).
  BuildRunBuildFlags? buildFlags(ArgResults results, {String? target}) {
    final BuildFlags flags;
    try {
      flags = BuildFlags.fromArgs(results, target: target);
    } on Object catch (error) {
      logger.detail('Could not read build flags for build history: $error');
      return null;
    }
    return BuildRunBuildFlags(
      dartDefineCount: flags.dartDefines.length,
      dartDefines: flags.dartDefines,
      target: flags.target,
    );
  }

  static BuildRunFailureReason _reasonFor(ProcessExit exit) => switch (exit) {
    ApiErrorExit() => BuildRunFailureReason.serverRejected,
    PromptDeclinedExit() => BuildRunFailureReason.canceled,
    _ => BuildRunFailureReason.other,
  };

  Future<void> _send(
    BuildRun run, {
    required BuildRunOutcome outcome,
    required Future<Json> Function() metadata,
    BuildRunFailureReason? reason,
  }) async {
    final appId = run.appId;
    if (appId == null) return;
    final duration = clock.now().difference(run.startedAt);
    final debugBundle = run.writtenDebugBundle;
    final CreateBuildRunResponse response;
    try {
      final request = CreateBuildRunRequest(
        runId: run.runId,
        command: run.command,
        platform: run.platform,
        outcome: outcome,
        reason: reason,
        releaseId: run.releaseId,
        patchId: run.patchId,
        startedAt: run.startedAt.toUtc(),
        durationMs: duration.inMilliseconds,
        dryRun: run.dryRun,
        metadata: run.metadata ?? await _tryMetadata(metadata),
        buildFlags: run.buildFlags,
        artifacts: debugBundle == null
            ? null
            : [
                CreateRunArtifact(
                  kind: RunArtifactKind.debugBundle,
                  sizeBytes: debugBundle.lengthSync(),
                ),
              ],
        shareDebugInfo: run.shareDebugInfo ? true : null,
      );
      response = await codePushClientWrapper.codePushClient
          .createBuildRun(appId: appId, request: request)
          .timeout(sendTimeout);
    } on Object catch (error) {
      // Build history is a record for the customer, not part of the run: a
      // run that worked must not fail because it couldn't be recorded.
      logger.detail('Could not record this run in build history: $error');
      return;
    }
    for (final upload in response.artifactUploads ?? <RunArtifactUpload>[]) {
      if (upload.kind != RunArtifactKind.debugBundle || debugBundle == null) {
        continue;
      }
      await _shareDebugBundle(upload, debugBundle);
    }
  }

  /// Uploads [file] to [upload]. Like the record, sharing never changes the
  /// run's result: a failed upload is reported and the run goes on.
  Future<void> _shareDebugBundle(RunArtifactUpload upload, File file) async {
    try {
      await codePushClientWrapper.codePushClient.uploadRunArtifact(
        upload: upload,
        path: file.path,
      );
    } on Object catch (error) {
      logger
        ..warn('Could not share debugging information with Shorebird.')
        ..detail('Debug bundle upload failed: $error');
      return;
    }
    final why = switch (upload.sharedBy) {
      RunArtifactSharedBy.setting => 'org setting',
      RunArtifactSharedBy.flag => '--share-debug-info',
    };
    logger.info('Shared debugging information with Shorebird ($why)');
  }

  /// [metadata], with the build trace summary written first if the run
  /// stopped before the command wrote it, or null if it can't be built.
  Future<Json?> _tryMetadata(Future<Json> Function() metadata) async {
    try {
      if (buildTraceSession.summary == null) {
        artifactBuilder.writeBuildTraceSummary();
      }
      return await metadata();
    } on Object catch (error) {
      logger.detail('Could not describe this run for build history: $error');
      return null;
    }
  }
}
