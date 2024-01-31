import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

// A reference to a [ShorebirdProcess] instance.
final processRef = create(ShorebirdProcess.new);

// The [ShorebirdProcess] instance available in the current zone.
ShorebirdProcess get process => read(processRef);

/// A wrapper around [Process] that replaces executables to Shorebird-vended
/// versions.
// This may need a better name, since it returns "Process" it's more a
// "ProcessFactory" than a "Process".
class ShorebirdProcess {
  ShorebirdProcess({
    ProcessWrapper? processWrapper, // For mocking ShorebirdProcess.
  }) : processWrapper = processWrapper ?? ProcessWrapper();

  final ProcessWrapper processWrapper;

  Future<ShorebirdProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
    bool useVendedFlutter = true,
  }) async {
    final resolvedEnvironment = _resolveEnvironment(
      environment,
      executable: executable,
      useVendedFlutter: useVendedFlutter,
    );
    final resolvedExecutable = _resolveExecutable(
      executable,
      useVendedFlutter: useVendedFlutter,
    );
    final resolvedArguments = _resolveArguments(
      executable,
      arguments,
      useVendedFlutter: useVendedFlutter,
    );
    logger.detail(
      '''[Process.run] $resolvedExecutable ${resolvedArguments.join(' ')}${workingDirectory == null ? '' : ' (in $workingDirectory)'}''',
    );

    final result = await processWrapper.run(
      resolvedExecutable,
      resolvedArguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );

    _logResult(result);

    return result;
  }

  ShorebirdProcessResult runSync(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
    bool useVendedFlutter = true,
  }) {
    final resolvedEnvironment = _resolveEnvironment(
      environment,
      executable: executable,
      useVendedFlutter: useVendedFlutter,
    );
    final resolvedExecutable = _resolveExecutable(
      executable,
      useVendedFlutter: useVendedFlutter,
    );
    final resolvedArguments = _resolveArguments(
      executable,
      arguments,
      useVendedFlutter: useVendedFlutter,
    );
    logger.detail(
      '''[Process.runSync] $resolvedExecutable ${resolvedArguments.join(' ')}${workingDirectory == null ? '' : ' (in $workingDirectory)'}''',
    );

    final result = processWrapper.runSync(
      resolvedExecutable,
      resolvedArguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );

    _logResult(result);

    return result;
  }

  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool runInShell = false,
    bool useVendedFlutter = true,
  }) {
    final resolvedEnvironment = environment ?? {};
    if (useVendedFlutter) {
      // Note: this will overwrite existing environment values.
      resolvedEnvironment.addAll(
        _environmentOverrides(executable: executable),
      );
    }
    final resolvedExecutable = _resolveExecutable(
      executable,
      useVendedFlutter: useVendedFlutter,
    );
    final resolvedArguments = _resolveArguments(
      executable,
      arguments,
      useVendedFlutter: useVendedFlutter,
    );
    logger.detail(
      '[Process.start] $resolvedExecutable ${resolvedArguments.join(' ')}',
    );

    return processWrapper.start(
      resolvedExecutable,
      resolvedArguments,
      runInShell: runInShell,
      environment: resolvedEnvironment,
    );
  }

  Map<String, String> _resolveEnvironment(
    Map<String, String>? baseEnvironment, {
    required String executable,
    required bool useVendedFlutter,
  }) {
    final resolvedEnvironment = baseEnvironment ?? {};
    if (useVendedFlutter) {
      // Note: this will overwrite existing environment values.
      resolvedEnvironment.addAll(
        _environmentOverrides(executable: executable),
      );
    }

    return resolvedEnvironment;
  }

  String _resolveExecutable(
    String executable, {
    required bool useVendedFlutter,
  }) {
    if (useVendedFlutter && executable == 'flutter') {
      return shorebirdEnv.flutterBinaryFile.path;
    }

    return executable;
  }

  List<String> _resolveArguments(
    String executable,
    List<String> arguments, {
    required bool useVendedFlutter,
  }) {
    var resolvedArguments = arguments;
    if (executable == 'flutter') {
      // Ideally we'd use this for all commands, but not all commands recognize
      // `--verbose` and some error if it's provided.
      if (logger.level == Level.verbose) {
        resolvedArguments = [...resolvedArguments, '--verbose'];
      }

      if (useVendedFlutter && engineConfig.localEngine != null) {
        resolvedArguments = [
          '--local-engine-src-path=${engineConfig.localEngineSrcPath}',
          '--local-engine=${engineConfig.localEngine}',
          '--local-engine-host=${engineConfig.localEngineHost}',
          ...resolvedArguments,
        ];
      }
    }

    return resolvedArguments;
  }

  void _logResult(ShorebirdProcessResult result) {
    logger.detail('Exited with code ${result.exitCode}');

    final stdout = result.stdout as String?;
    if (stdout != null && stdout.isNotEmpty) {
      logger.detail('''

stdout:
$stdout''');
    }

    final stderr = result.stderr as String?;
    if (stderr != null && stderr.isNotEmpty) {
      logger.detail('''

stderr:
$stderr''');
    }
  }

  Map<String, String> _environmentOverrides({
    required String executable,
  }) {
    if (executable == 'flutter') {
      // If this ever changes we also need to update the `shorebird` shell
      // wrapper which downloads runs Flutter to fetch artifacts the first time.
      return {'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev'};
    }

    return {};
  }
}

class ShorebirdProcessResult {
  const ShorebirdProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
}

// coverage:ignore-start
@visibleForTesting
class ProcessWrapper {
  Future<ShorebirdProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
    );
    return ShorebirdProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  ShorebirdProcessResult runSync(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    final result = Process.runSync(
      executable,
      arguments,
      environment: environment,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
    );
    return ShorebirdProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  Future<Process> start(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
  }) {
    return Process.start(
      executable,
      arguments,
      runInShell: runInShell,
      environment: environment,
    );
  }
}
// coverage:ignore-end
