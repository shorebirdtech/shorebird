import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [ShorebirdTools] instance.
final shorebirdToolsRef = create(ShorebirdTools.new);

/// The [ShorebirdTools] instance available in the current zone.
ShorebirdTools get shorebirdTools => read(shorebirdToolsRef);

/// {@template package_failed_exception}
/// An exception thrown when a package fails.
/// {@endtemplate}
class PackageFailedException implements Exception {
  /// {@macro package_failed_exception}
  PackageFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A wrapper around the `shorebird_tools` executable.
///
/// Used to access many commands related to Shorebird's flutter tooling.
class ShorebirdTools {
  /// Returns if the the current flutter version supports this tool.
  ///
  /// This should be used to check if the tool is supported before running
  /// any commands.
  bool isSupported() {
    return shorebirdToolsDirectory.existsSync();
  }

  Directory get shorebirdToolsDirectory {
    final dir = Directory(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'packages',
        'shorebird_tools',
      ),
    );
    logger.info(dir.path);
    return dir;
  }

  Future<ShorebirdProcessResult> _run(List<String> args) {
    return process.run(
      shorebirdEnv.dartBinaryFile.path,
      [
        'run',
        'shorebird_tools',
        'package',
        ...args,
      ],
      workingDirectory: shorebirdToolsDirectory.path,
    );
  }

  Future<void> package({
    required String patchPath,
    required String outputPath,
  }) async {
    final packageArguments = [
      '-p',
      patchPath,
      '-o',
      outputPath,
    ];

    final result = await _run(packageArguments);

    if (result.exitCode != ExitCode.success.code) {
      throw PackageFailedException(
        '''
Failed to create package (exit code ${result.exitCode}).
  stdout: ${result.stdout}
  stderr: ${result.stderr}''',
      );
    }
  }
}
