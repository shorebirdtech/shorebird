import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/patch/android_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template android_patcher}
/// Functions to create an Android patch.
/// {@endtemplate}
class AndroidPatcher extends Patcher with AndroidPatcherMixin {
  /// {@macro android_patcher}
  AndroidPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  /// Android versions prior to 3.24.2 have a bug that can cause patches to
  /// be erroneously uninstalled.
  /// https://github.com/shorebirdtech/updater/issues/211 was fixed in 3.24.2
  static final updaterPatchErrorWarning =
      '''
Your version of flutter contains a known issue that can cause patches to be erroneously uninstalled in apps that use package:flutter_foreground_task or other plugins that start their own Flutter engines.
This issue was fixed in Flutter 3.24.2. Please upgrade to a newer version of Flutter to avoid this issue.

See more info about the issue ${link(uri: Uri.parse('https://github.com/shorebirdtech/updater/issues/211'), message: 'on Github')}
''';

  /// The patch AAB built by [buildPatchArtifact], which
  /// [createPatchArtifacts] extracts each `libapp.so` from.
  /// See https://github.com/shorebirdtech/shorebird/issues/3388.
  File? _patchAab;

  @override
  ReleaseType get releaseType => ReleaseType.android;

  @override
  String get primaryReleaseArtifactArch => 'aab';

  @override
  String? get supplementaryReleaseArtifactArch => 'android_supplement';

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
    localArchive: patchArchive,
    releaseArchive: releaseArchive,
    archiveDiffer: const AndroidArchiveDiffer(),
    allowAssetChanges: allowAssetDiffs,
    allowNativeChanges: allowNativeDiffs,
    showDexDiff: showDexDiff,
  );

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: doctor.androidCommandValidators,
  );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final flutterVersion = await shorebirdFlutter.getVersion();
    // Android versions prior to 3.24.2 have a bug that can cause patches to
    // be erroneously uninstalled.
    // https://github.com/shorebirdtech/updater/issues/211 was fixed in 3.24.2
    if (flutterVersion != null && flutterVersion < Version(3, 24, 2)) {
      logger.warn(updaterPatchErrorWarning);
    }

    final buildArgs = [
      ...argResults.forwardedArgs,
      ...extraBuildArgs,
      ...buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
    ];
    final aabFile = await artifactBuilder.buildAppBundle(
      flavor: flavor,
      target: target,
      targetPlatforms: releaseTargetPlatforms,
      args: buildArgs,
      base64PublicKey: await getEncodedPublicKey(),
    );

    // When the built .aab never packaged libapp.so, fail fast with an accurate
    // explanation rather than the generic "cannot find artifacts" message or
    // silently diffing against a stale strip output
    // (https://github.com/shorebirdtech/shorebird/issues/3813).
    final missingLibappMessage =
        await ArtifactManager.describeMissingLibappInAab(aabFile);
    if (missingLibappMessage != null) {
      throw CommandError(
        message: missingLibappMessage,
        exitCode: ExitCode.software,
      );
    }

    _patchAab = aabFile;
    return aabFile;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
    Duration downloadMessageTimeout = const Duration(minutes: 1),
  }) async {
    final releaseArtifactPaths = await downloadAndroidReleaseArtifacts(
      appId: appId,
      releaseId: releaseId,
      downloadMessageTimeout: downloadMessageTimeout,
    );

    // [buildPatchArtifact] runs before this and records the patch AAB; with
    // no AAB (a direct call without it) this reads AGP's stripped output.
    return ArtifactManager.withAndroidArchsDirectoryFromAab(
      projectRoot: projectRoot,
      flavor: flavor,
      aab: _patchAab,
      action: (patchArchsBuildDir) async {
        if (patchArchsBuildDir == null) {
          throw CommandError(
            message:
                'Cannot find patch build artifacts: no libapp.so in the '
                'built .aab or in '
                'build/app/intermediates/stripped_native_libs.',
            hint:
                'Clear the cache and try again, and file an issue at '
                'https://github.com/shorebirdtech/shorebird/issues/new if '
                'this persists. Run: shorebird cache clean',
            exitCode: ExitCode.software,
          );
        }

        return createAndroidPatchArtifactBundles(
          releaseArtifactPaths: releaseArtifactPaths,
          patchArchsDir: patchArchsBuildDir,
        );
      },
    );
  }
}
