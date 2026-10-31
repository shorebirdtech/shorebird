import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Shared logic for patchers whose release artifacts are per-architecture
/// libapp.so files (Android app bundles and Android archives).
mixin AndroidPatcherMixin on Patcher {
  /// The release's per-architecture artifacts, fetched by
  /// [prepareForRelease], with the id of the release they belong to.
  ({int releaseId, Map<Arch, ReleaseArtifact> artifacts})? _releaseArtifacts;

  @override
  Future<void> prepareForRelease({
    required String appId,
    required Release release,
  }) async {
    _releaseArtifacts = (
      releaseId: release.id,
      artifacts: await _fetchReleaseArtifacts(
        appId: appId,
        releaseId: release.id,
      ),
    );
  }

  Future<Map<Arch, ReleaseArtifact>> _fetchReleaseArtifacts({
    required String appId,
    required int releaseId,
  }) => codePushClientWrapper.getReleaseArtifacts(
    appId: appId,
    releaseId: releaseId,
    architectures: AndroidArch.availableAndroidArchs,
    platform: releaseType.releasePlatform,
  );

  /// The architectures to build the patch for: those the release has, so a
  /// release built for one architecture doesn't pay for building three.
  ///
  /// Null, which builds Flutter's default architectures, when the release is
  /// not known yet (the build that reads the release version from the
  /// patch), when the release has no per-architecture artifacts, or when the
  /// user passed their own `--target-platform` after `--`. Architectures the
  /// patch builds beyond the release's are never diffed, so building them
  /// only costs time.
  Iterable<Arch>? get releaseTargetPlatforms {
    final archs = _releaseArtifacts?.artifacts.keys;
    if (archs == null || archs.isEmpty) return null;
    final userTargetPlatform = argResults.forwardedArgs.any(
      (arg) =>
          arg == '--target-platform' || arg.startsWith('--target-platform='),
    );
    if (userTargetPlatform) return null;
    logger.detail(
      "Building the patch for the release's architectures: "
      '${archs.map((arch) => arch.targetPlatformCliArg).join(', ')}',
    );
    return archs;
  }

  /// Downloads the per-architecture release artifacts for [releaseId] and
  /// returns the local path of each, keyed by architecture.
  ///
  /// If the downloads take longer than [downloadMessageTimeout], points the
  /// user at the known Windows download issue.
  Future<Map<Arch, String>> downloadAndroidReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Duration downloadMessageTimeout,
  }) async {
    final releaseArtifacts = switch (_releaseArtifacts) {
      (releaseId: final id, :final artifacts) when id == releaseId => artifacts,
      _ => await _fetchReleaseArtifacts(appId: appId, releaseId: releaseId),
    };
    final releaseArtifactPaths = <Arch, String>{};
    final numArtifacts = releaseArtifacts.length;

    // Direct users to https://github.com/shorebirdtech/shorebird/issues/2532
    // until we can provide a better solution.
    var artifactsDownloadCompleted = false;
    unawaited(
      Future<void>.delayed(downloadMessageTimeout).then((_) {
        if (artifactsDownloadCompleted) {
          return;
        }
        logger.info(
          '''
It seems like your download is taking longer than expected. If you are on Windows, this is a known issue.
Please refer to ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/2532'))} for potential workarounds.''',
        );
      }),
    );

    for (final (i, releaseArtifact) in releaseArtifacts.entries.indexed) {
      try {
        final releaseArtifactFile = await artifactManager
            .downloadReleaseArtifact(
              releaseArtifact.value,
              message: 'Downloading release artifact ${i + 1}/$numArtifacts',
            );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactFile.path;
      } on Exception catch (error) {
        throw CommandError(
          message: 'Could not download the release artifact: $error',
          hint: 'Run the command again once that is fixed.',
          exitCode: ExitCode.software,
        );
      }
    }

    artifactsDownloadCompleted = true;
    return releaseArtifactPaths;
  }

  /// Diffs the libapp.so under [patchArchsDir] for each architecture in
  /// [releaseArtifactPaths] against that architecture's release artifact.
  ///
  /// Architectures the patch build did not produce are skipped with a warning
  /// naming them, and the command exits if none were produced.
  Future<Map<Arch, PatchArtifactBundle>> createAndroidPatchArtifactBundles({
    required Map<Arch, String> releaseArtifactPaths,
    required Directory patchArchsDir,
  }) async {
    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};
    final skippedArchs = <Arch>[];
    final createDiffProgress = logger.progress('Creating patch artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final arch = releaseArtifactPath.key;
      final patchArtifactPath = p.join(
        patchArchsDir.path,
        arch.androidBuildPath,
        'libapp.so',
      );
      logger.detail('Creating artifact for $patchArtifactPath');
      final patchArtifact = File(patchArtifactPath);
      // Skip archs the build didn't produce (ndk.abiFilters / splits.abi /
      // jniLibs.excludes). Without this, a release built for a subset of
      // archs can't be patched without hitting PathNotFoundException
      // (https://github.com/shorebirdtech/shorebird/issues/3388).
      if (!patchArtifact.existsSync()) {
        logger.detail(
          'Skipping ${arch.arch}: no libapp.so at $patchArtifactPath. '
          'This is expected if the project excludes this ABI from packaging.',
        );
        skippedArchs.add(arch);
        continue;
      }
      patchArtifactBundles[arch] = await createDiffBundle(
        arch: arch,
        releaseArtifactPath: releaseArtifactPath.value,
        patchArtifactPath: patchArtifactPath,
        progress: createDiffProgress,
      );
    }
    if (patchArtifactBundles.isEmpty) {
      createDiffProgress.fail();
      throw CommandError(
        // No path here: patchArchsDir may be a temporary directory that is
        // deleted before the command exits.
        message:
            'No patch artifacts produced: the patch build has no libapp.so '
            'for any architecture in the release.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }
    createDiffProgress.complete();

    // A partial patch still succeeds, so name the architectures it leaves
    // behind. Without this the omission is only visible at --verbose, and a
    // patch that reaches a fraction of the install base looks identical to one
    // that is merely slow to roll out.
    if (skippedArchs.isNotEmpty) {
      // androidBuildPath, not arch: the message points at Gradle packaging
      // config, and only the ABI names appear there.
      final skipped = skippedArchs
          .map((arch) => arch.androidBuildPath)
          .join(', ');
      final patched = patchArtifactBundles.keys
          .map((arch) => arch.androidBuildPath)
          .join(', ');
      logger.warn('''
This patch does not cover every architecture in the release.

  Patched: $patched
  Skipped: $skipped

Devices on the skipped architectures stay on the release and will not receive
this patch.

The patch build produced no libapp.so for them, so it and the release build
disagree on which architectures to compile. If that is deliberate, such as an
excludes rule under packaging.jniLibs, no device runs the skipped
architectures and there is nothing to do. Otherwise rebuild the patch using
the same Android configuration and Flutter version as the release.''');
    }

    return patchArtifactBundles;
  }
}
