import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template android_patcher}
/// Functions to create an Android patch.
/// {@endtemplate}
class AndroidPatcher extends Patcher {
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
  );

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

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
      args: buildArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );

    final patchArchsBuildDir = ArtifactManager.androidArchsDirectory(
      projectRoot: projectRoot,
      flavor: flavor,
    );

    if (patchArchsBuildDir == null) {
      logger
        ..err('Cannot find patch build artifacts.')
        ..info('''
Please run `shorebird cache clean` and try again. If the issue persists, please
file a bug report at https://github.com/shorebirdtech/shorebird/issues/new.

Looked in:
  - build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib
  - build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib
  - build/app/intermediates/stripped_native_libs/release/out/lib
  - build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib''');
      throw ProcessExit(ExitCode.software.code);
    }
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

    final patchArchsBuildDir = ArtifactManager.androidArchsDirectory(
      projectRoot: projectRoot,
      flavor: flavor,
    );
    if (patchArchsBuildDir == null) {
      logger.err('Could not find patch artifacts');
      throw ProcessExit(ExitCode.software.code);
    }

    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};
    final createDiffProgress = logger.progress('Creating patch artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final arch = releaseArtifactPath.key;
      final patchArtifactPath = p.join(
        patchArchsBuildDir.path,
        arch.androidBuildPath,
        'libapp.so',
      );
      logger.detail('Creating artifact for $patchArtifactPath');
      final patchArtifact = File(patchArtifactPath);
      final hash = sha256.convert(await patchArtifact.readAsBytes()).toString();
      final hashSignature = await signHash(hash);

      try {
        final diffPath = await artifactManager.createDiff(
          releaseArtifactPath: releaseArtifactPath.value,
          patchArtifactPath: patchArtifactPath,
        );
        patchArtifactBundles[releaseArtifactPath.key] = PatchArtifactBundle(
          arch: arch.arch,
          path: diffPath,
          hash: hash,
          size: await File(diffPath).length(),
          hashSignature: hashSignature,
        );
      } on Exception catch (error) {
        createDiffProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }
    }
    createDiffProgress.complete();
    return patchArtifactBundles;
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    return shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
      artifact.path,
    );
  }
}
