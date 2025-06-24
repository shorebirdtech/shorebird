import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [ProcessWrapper] instance.
final processRef = create(ProcessWrapper.new);

/// The [ProcessWrapper] instance available in the current zone.
ProcessWrapper get process => read(processRef);

/// {@template shorebird_process_result}
/// Result from running a process.
/// {@endtemplate}
class ShorebirdProcessResult {
  /// {@macro shorebird_process_result}
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
class ProcessWrapper {
  /// Runs the process and returns the result.
  Future<ShorebirdProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
    bool? runInShell,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: environment,
      // TODO(felangel): refactor to never runInShell
      runInShell: runInShell ?? Platform.isWindows,
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
    bool? runInShell,
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(
      executable,
      arguments,
      // TODO(felangel): refactor to never runInShell
      runInShell: runInShell ?? Platform.isWindows,
      environment: environment,
      workingDirectory: workingDirectory,
      mode: mode,
    );
  }

  /// Starts a process, streams the output in real-time, and returns the exit
  /// code.
  Future<int> stream(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool? runInShell,
    String? workingDirectory,
  }) async {
    final process = await start(
      executable,
      arguments,
      environment: environment,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }
}
