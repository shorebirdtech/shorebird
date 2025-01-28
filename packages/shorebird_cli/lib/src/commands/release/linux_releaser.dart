import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template linux_releaser}
/// Functions to create a linux release.
/// {@endtemplate}
class LinuxReleaser extends Releaser {
  /// {@macro linux_releaser}
  LinuxReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  Future<void> assertArgsAreValid() async {}

  @override
  Future<void> assertPreconditions() async {}

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildAppBundleProgress = logger.progress(
      'Building Linux application with Flutter $flutterVersionString',
    );

    try {
      await artifactBuilder.buildLinuxApp();
    } on Exception catch (e) {
      logger.err('Failed to build Linux application: $e');
      throw ProcessExit(ExitCode.software.code);
    }

    buildAppBundleProgress.complete(
      'Built Linux application with Flutter $flutterVersionString',
    );

    return _bundleDirectory;
  }

  Directory get _bundleDirectory => Directory(
        p.join(
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
        ),
      );

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    // TODO
    return '1.0.0+1';
  }

  @override
  String get postReleaseInstructions => 'TODO: post release instructions here';

  @override
  ReleaseType get releaseType => ReleaseType.linux;

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    await codePushClientWrapper.createLinuxReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      bundlePath: _bundleDirectory.path,
    );
  }
}
