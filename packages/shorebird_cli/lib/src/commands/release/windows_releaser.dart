import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template windows_releaser}
/// Functions to create a Windows release.
/// {@endtemplate}
class WindowsReleaser extends Releaser {
  /// {@macro windows_releaser}
  WindowsReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.windows;

  @override
  Future<void> assertArgsAreValid() async {
    // TODO: implement assertArgsAreValid
  }

  @override
  Future<void> assertPreconditions() async {
    // TODO: implement assertPreconditions
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildAppBundleProgress = logger.detailProgress(
      'Building Windows app with Flutter $flutterVersionString',
    );

    final Directory releaseDir;
    try {
      releaseDir = await artifactBuilder.buildWindowsApp(
        flavor: flavor,
        target: target,
        args: argResults.forwardedArgs,
        buildProgress: buildAppBundleProgress,
      );
      buildAppBundleProgress.complete();
    } catch (e) {
      buildAppBundleProgress.fail(e.toString());
      throw ProcessExit(ExitCode.software.code);
    }

    return releaseDir;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final exe = (releaseArtifactRoot as Directory)
        .listSync()
        .whereType<File>()
        .firstWhere(
          (entity) => p.extension(entity.path) == '.exe',
          orElse: () => throw Exception('No .exe found in release artifact'),
        );
    return getExeVersionString(exe);
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot()!;
    final releaseDir = Directory(
      p.join(
        projectRoot.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
      ),
    );

    final zippedRelease = await releaseDir.zipToTempFile();

    await codePushClientWrapper.createWindowsReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      projectRoot: projectRoot.path,
      releaseZipPath: zippedRelease.path,
    );
  }

  @override
  String get postReleaseInstructions => 'TODO';
}
