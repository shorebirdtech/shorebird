import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/bundle_dependencies.dart';
import 'package:shorebird_cli/src/archive_analysis/dart_bridge_analyzer.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/patch/android_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
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

  /// Flutter versions prior to 3.24.2 have a bug that can cause patches to
  /// be erroneously uninstalled on Android. See the November 17, 2025 note at
  /// https://docs.shorebird.dev/getting-started/flutter-version/#flutter-version-notes
  static final updaterPatchErrorWarning =
      '''
Your version of flutter contains a known issue that can cause patches to be erroneously uninstalled in apps that use package:flutter_foreground_task or other plugins that start their own Flutter engines.
This issue was fixed in Flutter 3.24.2, and in Flutter 3.24.1 for releases created with Shorebird 1.3.1 or later. Please upgrade to a newer version of Flutter to avoid this issue.

See more info about the issue ${link(uri: Uri.parse('https://docs.shorebird.dev/getting-started/flutter-version/#flutter-version-notes'), message: 'in the Shorebird docs')}
''';

  /// The patch AAB built by [buildPatchArtifact], which
  /// [createPatchArtifacts] extracts each `libapp.so` from.
  /// See https://github.com/shorebirdtech/shorebird/issues/3388.
  File? _patchAab;

  /// Optional compiled Dart kernel (`app.dill`) inspected during
  /// [assertUnpatchableDiffs] to verify `@Native` and platform channel bridge
  /// contracts against the release binary.
  File? appDill;

  /// The Gradle project property that Shorebird's Flutter fork reads to pin
  /// Maven dependency versions: the path of a file listing one
  /// `group:artifact:version` per line.
  @visibleForTesting
  static const pinnedDependenciesProjectProperty =
      'shorebird.pinned-dependencies';

  /// The `group:artifact:version` of each Maven library in [releaseAab]'s
  /// `dependencies.pb`, sorted, so the patch resolves the same versions as
  /// the release. Empty when there is no release AAB or it has no readable
  /// `dependencies.pb`: the patch then builds unpinned, as before.
  @visibleForTesting
  static List<String> releasePinnedDependencies(File? releaseAab) {
    if (releaseAab == null || !releaseAab.existsSync()) return const [];
    final Map<String, String> dependencies;
    try {
      final input = InputFileStream(releaseAab.path);
      Uint8List? bytes;
      try {
        final file = ZipDecoder()
            .decodeStream(input)
            .findFile(bundleDependenciesPath);
        if (file != null && file.isFile) bytes = file.content;
      } finally {
        input.closeSync();
      }
      if (bytes == null) return const [];
      dependencies = parseBundleDependencies(bytes);
      // A damaged archive can throw an Error (a RangeError from
      // package:archive) as well as an Exception. Either way, build unpinned.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      logger.detail('Not pinning Maven versions to the release: $error');
      return const [];
    }
    final coordinates = <String>{};
    for (final MapEntry(key: name, value: version) in dependencies.entries) {
      // name is group:artifact, plus :classifier when there is one; a
      // version applies to every classifier of a module.
      final parts = name.split(':');
      if (parts.length < 2 || version.isEmpty) continue;
      coordinates.add('${parts[0]}:${parts[1]}:$version');
    }
    return coordinates.toList()..sort();
  }

  /// Shown when a patch build with pinned Maven versions fails: pinning is
  /// the likeliest cause the customer can't see in their own build files.
  @visibleForTesting
  static String pinnedDependenciesBuildHint(int count) => '''
This patch was built with $count Maven libraries pinned to the versions your release used, so that it matches what devices run. If the error names a library you updated since the release, rerun with --no-pin-dependencies to use the versions in your Gradle files. A patch can't change native code, so the patch may then be reported as having native changes.''';

  /// Whether this Flutter has the fork's init script that reads
  /// [pinnedDependenciesProjectProperty]. Older ones ignore the property, so a
  /// failed build there has nothing to do with pinning.
  bool get _flutterPinsDependencies => File(
    p.join(
      shorebirdEnv.flutterDirectory.path,
      'packages',
      'flutter_tools',
      'gradle',
      'shorebird_pin_dependencies_init.gradle',
    ),
  ).existsSync();

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
  }) async {
    final status = await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArchive: patchArchive,
      releaseArchive: releaseArchive,
      archiveDiffer: const AndroidArchiveDiffer(),
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
      showDexDiff: showDexDiff,
    );

    final dillFile =
        appDill ?? File(p.join(projectRoot.path, 'build', 'app.dill'));
    if (dillFile.existsSync() && releaseArchive.existsSync()) {
      final fileSetDiff = patchArchive.existsSync()
          ? await const AndroidArchiveDiffer().changedFiles(
              releaseArchive.path,
              patchArchive.path,
            )
          : null;
      final bridgeResult = const DartBridgeAnalyzer().analyze(
        dillBytes: dillFile.readAsBytesSync(),
        releaseArchivePath: releaseArchive.path,
        fileSetDiff: fileSetDiff,
      );
      for (final diagnostic in bridgeResult.diagnostics) {
        logger.warn(yellow.wrap(diagnostic.describe()));
      }
    }

    return status;
  }

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: doctor.androidCommandValidators,
  );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final flutterVersion = await shorebirdFlutter.getVersion();
    // Flutter versions prior to 3.24.2 (except the patched 3.24.1 revision)
    // have a bug that can cause patches to be erroneously uninstalled on
    // Android. See [updaterPatchErrorWarning].
    if (flutterVersion != null &&
        !updaterPatchErrorFixConstraint.isSatisfiedBy(
          version: flutterVersion,
          revision: shorebirdEnv.flutterRevision,
        )) {
      logger.warn(updaterPatchErrorWarning);
    }

    final pinnedDependencies = pinDependencies
        ? releasePinnedDependencies(releaseArchive)
        : const <String>[];
    if (!pinDependencies) {
      logger.detail(
        "Not pinning Maven versions to the release's: --no-pin-dependencies.",
      );
    } else if (pinnedDependencies.isNotEmpty) {
      logger.detail(
        "Pinning ${pinnedDependencies.length} Maven libraries to the release's "
        'versions (on Flutter versions that support it).',
      );
    }
    final pinsDir = pinnedDependencies.isEmpty
        ? null
        : Directory.systemTemp.createTempSync('shorebird_pins_');
    final File aabFile;
    try {
      final pinsFile = pinsDir == null
          ? null
          : (File(p.join(pinsDir.path, 'pinned_dependencies.txt'))
              ..writeAsStringSync('${pinnedDependencies.join('\n')}\n'));
      aabFile = await artifactBuilder.buildAppBundle(
        flavor: flavor,
        target: target,
        targetPlatforms: releaseTargetPlatforms,
        args: [
          ...argResults.forwardedArgs,
          ...extraBuildArgs,
          ...buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
          // Read by shorebird_pin_dependencies_init.gradle in Shorebird's
          // Flutter fork. Flutter versions without it ignore the property.
          if (pinsFile != null)
            [
              '--android-project-arg=$pinnedDependenciesProjectProperty',
              pinsFile.path,
            ].join('='),
        ],
        base64PublicKey: await getEncodedPublicKey(),
      );
    } on ArtifactBuildException catch (e) {
      if (pinnedDependencies.isEmpty || !_flutterPinsDependencies) rethrow;
      throw ArtifactBuildException(
        e.message,
        fixRecommendation: [
          pinnedDependenciesBuildHint(pinnedDependencies.length),
          ?e.fixRecommendation,
        ].join('\n'),
      );
    } finally {
      pinsDir?.deleteTemporarySync();
    }

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

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    return shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
      artifact.path,
    );
  }
}
