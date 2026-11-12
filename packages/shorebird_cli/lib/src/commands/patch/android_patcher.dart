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

  /// Generates a Gradle `--init-script` that pins transitive Maven
  /// dependencies via `resolutionStrategy.force(...)` to the exact versions
  /// recorded in the release bundle's `dependencies.pb`.
  @visibleForTesting
  static String generateGradleInitScript(Map<String, String> dependencies) {
    final sortedNames = dependencies.keys.toList()..sort();
    final forcedCoordinates = <String>[];
    final seenCoordinates = <String>{};
    for (final name in sortedNames) {
      final version = dependencies[name];
      if (version == null || version.isEmpty) continue;
      final parts = name.split(':');
      if (parts.length < 2) continue;
      final coordinate = '${parts[0]}:${parts[1]}:$version';
      if (seenCoordinates.add(coordinate)) {
        forcedCoordinates.add(coordinate);
      }
    }
    final buffer = StringBuffer()
      ..writeln('allprojects {')
      ..writeln('  configurations.all {');
    for (final coordinate in forcedCoordinates) {
      buffer.writeln("    resolutionStrategy.force('$coordinate')");
    }
    buffer
      ..writeln('  }')
      ..writeln('}');
    return buffer.toString();
  }

  static Map<String, String>? _extractReleaseDependencies(File? releaseAab) {
    if (releaseAab == null || !releaseAab.existsSync()) return null;
    try {
      final input = InputFileStream(releaseAab.path);
      Uint8List? dependenciesBytes;
      try {
        final archive = ZipDecoder().decodeStream(input, verify: true);
        for (final file in archive.files) {
          if (file.isFile && file.name == bundleDependenciesPath) {
            dependenciesBytes = Uint8List.fromList(file.content);
            break;
          }
        }
      } finally {
        input.closeSync();
      }
      if (dependenciesBytes == null) return null;
      final parsed = parseBundleDependencies(dependenciesBytes);
      return parsed.isEmpty ? null : parsed;
      // If the release AAB has no valid dependencies.pb, skip pinning rather
      // than failing the patch build.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

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
  Future<File> buildPatchArtifact({
    String? releaseVersion,
    File? releaseArchive,
  }) async {
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

    Directory? initScriptDir;
    File? initScriptFile;
    final dependencies = _extractReleaseDependencies(
      releaseArchive ?? this.releaseArchive,
    );
    if (dependencies != null) {
      initScriptDir = Directory.systemTemp.createTempSync();
      initScriptFile = File(
        p.join(initScriptDir.path, 'shorebird-lock.init.gradle'),
      )..writeAsStringSync(generateGradleInitScript(dependencies));
    }

    final File aabFile;
    try {
      final buildArgs = [
        ...argResults.forwardedArgs,
        ...extraBuildArgs,
        ...buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
        if (initScriptFile != null) ...[
          '--init-script',
          initScriptFile.path,
        ],
      ];
      aabFile = await artifactBuilder.buildAppBundle(
        flavor: flavor,
        target: target,
        targetPlatforms: releaseTargetPlatforms,
        args: buildArgs,
        base64PublicKey: await getEncodedPublicKey(),
      );
    } finally {
      initScriptDir?.deleteTemporarySync();
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
