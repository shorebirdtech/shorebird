import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// {@template build_command}
///
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand with ShorebirdEngineMixin {
  /// {@macro build_command}
  BuildCommand({
    super.auth,
    super.buildCodePushClient,
    super.logger,
    super.runProcess,
  });

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';

  @override
  Future<int> run() async {
    if (auth.currentSession == null) {
      logger
        ..err('You must be logged in to build.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    try {
      await ensureEngineExists();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    final buildProgress = logger.progress('Building release ');
    try {
      await _build(shorebirdEnginePath);
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }

  Future<void> _build(String shorebirdEnginePath) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      // This is temporary because the Shorebird engine currently
      // only supports Android.
      'apk',
      '--release',
      '--local-engine-src-path',
      shorebirdEnginePath,
      '--local-engine',
      // This is temporary because the Shorebird engine currently
      // only supports Android arm64.
      'android_release_arm64',
    ];

    final result = await runProcess(
      executable,
      arguments,
      runInShell: true,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(
        'flutter',
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}
