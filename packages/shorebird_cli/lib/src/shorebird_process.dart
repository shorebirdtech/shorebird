import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [ShorebirdProcess] instance.
final processRef = create(ShorebirdProcess.new);

/// The [ShorebirdProcess] instance available in the current zone.
ShorebirdProcess get process => read(processRef);

/// A wrapper around [Process] that replaces executables to Shorebird-vended
/// versions.
// This may need a better name, since it returns "Process" it's more a
// "ProcessFactory" than a "Process".
class ShorebirdProcess {
  /// Creates a ShorebirdProcess.
  ShorebirdProcess({
    ProcessWrapper? processWrapper, // For mocking ShorebirdProcess.
  }) : processWrapper = processWrapper ?? ProcessWrapper();

  /// The underlying process wrapper.
  final ProcessWrapper processWrapper;

  /// Starts a process and streams the output in real-time.
  Future<ShorebirdProcessResult> stream(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool useVendedFlutter = true,
    String? workingDirectory,
    DetailProgress? progress,
    bool evalOutput = false,
  }) async {
    final process = await start(
      executable,
      arguments,
      environment: environment,
      useVendedFlutter: useVendedFlutter,
      workingDirectory: workingDirectory,
      mode:
          evalOutput ? ProcessStartMode.normal : ProcessStartMode.inheritStdio,
    );

    if (!evalOutput) {
      return ShorebirdProcessResult(
        exitCode: await process.exitCode,
        stdout: null,
        stderr: null,
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutSubscription = process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((String line) {
          stdoutBuffer.writeln(line);
          logger.detail(line);
          if (progress != null) {
            progress.updateDetailMessage(line);
          }
        });
    final stderrSubscription = process.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((String line) {
          stderrBuffer.writeln(line);
          logger.detail(red.wrap(line));
          if (progress != null) {
            progress.updateDetailMessage(line);
          }
        });

    // Wait for stdout to be fully processed
    // because process.exitCode may complete first causing flaky tests.
    await Future.wait<void>(<Future<void>>[
      stdoutSubscription.asFuture<void>(),
      stderrSubscription.asFuture<void>(),
    ]);

    // The streams as futures have already completed, so waiting for the
    // potentially async stream cancellation to complete likely has no benefit.
    // Further, some Stream implementations commonly used in tests don't
    // complete the Future returned here, which causes tests using
    // mocks/FakeAsync to fail when these Futures are awaited.
    unawaited(stdoutSubscription.cancel());
    unawaited(stderrSubscription.cancel());

    return ShorebirdProcessResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }

  /// Runs the process and returns the result.
  Future<ShorebirdProcessResult> run(
    String executable,
    List<String> arguments, {
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
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );

    _logResult(result);

    return result;
  }

  /// Runs the process synchronously and returns the result.
  ShorebirdProcessResult runSync(
    String executable,
    List<String> arguments, {
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
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );

    _logResult(result);

    return result;
  }

  /// Starts a new process running the executable with the specified arguments.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool useVendedFlutter = true,
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    final resolvedEnvironment = environment ?? {};
    if (useVendedFlutter) {
      // Note: this will overwrite existing environment values.
      resolvedEnvironment.addAll(_environmentOverrides(executable: executable));
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
      '''[Process.start] $resolvedExecutable ${resolvedArguments.join(' ')}${workingDirectory == null ? '' : ' (in $workingDirectory)'}''',
    );

    return processWrapper.start(
      resolvedExecutable,
      resolvedArguments,
      environment: resolvedEnvironment,
      workingDirectory: workingDirectory,
      mode: mode,
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
      resolvedEnvironment.addAll(_environmentOverrides(executable: executable));
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
      // *Always* run with `--verbose` to get more detailed logs. We rely on
      // this to determine the path to the app.dill file for iOS builds.
      // Ideally we'd use this for all commands, but not all commands recognize
      // `--verbose` and some error if it's provided.
      resolvedArguments = [...resolvedArguments, '--verbose'];

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

  Map<String, String> _environmentOverrides({required String executable}) {
    if (executable == 'flutter') {
      // If this ever changes we also need to update the `shorebird` shell
      // wrapper which downloads runs Flutter to fetch artifacts the first time.
      return {'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev'};
    }

    return {};
  }
}

/// Result from running a process.
class ShorebirdProcessResult {
  /// Creates a new [ShorebirdProcessResult].
  const ShorebirdProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The exit code of the process.
  final int exitCode;

  /// The standard output of the process.
  final dynamic stdout;

  /// The standard error of the process.
  final dynamic stderr;
}

/// A wrapper around [Process] that can be mocked for testing.
// coverage:ignore-start
@visibleForTesting
class ProcessWrapper {
  /// Runs the process and returns the result.
  Future<ShorebirdProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: Platform.isWindows,
      workingDirectory: workingDirectory,
    );
    return ShorebirdProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  /// Runs the process synchronously and returns the result.
  ShorebirdProcessResult runSync(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    final result = Process.runSync(
      executable,
      arguments,
      environment: environment,
      runInShell: Platform.isWindows,
      workingDirectory: workingDirectory,
    );
    return ShorebirdProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  /// Starts a new process running the executable with the specified arguments.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
      environment: environment,
      workingDirectory: workingDirectory,
      mode: mode,
    );
  }
}

// coverage:ignore-end
