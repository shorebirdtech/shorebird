import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [ShorebirdTool] instance.
final shorebirdToolRef = create(ShorebirdTool.new);

/// The [ShorebirdTool] instance available in the current zone.
ShorebirdTool get shorebirdTool => read(shorebirdToolRef);

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
class ShorebirdTool {

  /// Returns if the the current flutter version supports this tool.
  ///
  /// This should be used to check if the tool is supported before running
  /// any commands.
  bool isSupported() {
    return shorebirdToolDirectory.existsSync();
  }

  Directory get shorebirdToolDirectory {
    return Directory(
      p.join(
        shorebirdEnv.flutterDirectory.path,
        'packages',
        'shorebird_tools',
      ),
    );
  }

  Future<ShorebirdProcessResult> _run(List<String> args) {
    return process.run(
      'dart',
      [
        'run',
        'shorebird_tools',
        ...args,
      ],
      workingDirectory: shorebirdToolDirectory.path,
    );
  }

  Future<void> package({
    required String patchPath,
    required String outputPath,
  }) async {
    final packageArguments = [
      '-p', patchPath,
      '-o', outputPath,
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
