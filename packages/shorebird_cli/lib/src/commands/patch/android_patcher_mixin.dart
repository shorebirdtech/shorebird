import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Shared logic for patchers whose release artifacts are per-architecture
/// libapp.so files (Android app bundles and Android archives).
mixin AndroidPatcherMixin on Patcher {
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
    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      appId: appId,
      releaseId: releaseId,
      architectures: AndroidArch.availableAndroidArchs,
      platform: releaseType.releasePlatform,
    );
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
            .downloadWithProgressUpdates(
              Uri.parse(releaseArtifact.value.url),
              message: 'Downloading release artifact ${i + 1}/$numArtifacts',
            );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactFile.path;
      } on Exception {
        throw ProcessExit(ExitCode.software.code);
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
      createDiffProgress.fail(
        'No patch artifacts produced: no libapp.so found for any architecture '
        'under ${patchArchsDir.path}.',
      );
      throw ProcessExit(ExitCode.software.code);
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
