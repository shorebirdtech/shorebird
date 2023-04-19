import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
  Map<String, String>? environment,
  String? workingDirectory,
  bool useVendedFlutter,
});

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
  Map<String, String>? environment,
  bool useVendedFlutter,
});

/// A wrapper around [Process] that replaces executables to Shorebird-vended
/// versions.
abstract class ShorebirdProcess {
  @visibleForTesting
  static ProcessWrapper processWrapper = ProcessWrapper();

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
    bool useVendedFlutter = true,
  }) {
    final resolvedEnvironment = environment ?? {};
    if (useVendedFlutter) {
      // Note: this will overwrite existing environment values.
      resolvedEnvironment.addAll(
        _environmentOverrides(executable: executable),
      );
    }

    return processWrapper.run(
      useVendedFlutter ? _resolveExecutable(executable) : executable,
      arguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );
  }

  static Future<Process> start(
    String executable,
    List<String> argument, {
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

    return processWrapper.start(
      useVendedFlutter ? _resolveExecutable(executable) : executable,
      argument,
      runInShell: runInShell,
      environment: resolvedEnvironment,
    );
  }

  static String _resolveExecutable(String executable) {
    if (executable == 'flutter') {
      return ShorebirdEnvironment.flutterBinaryFile.path;
    }

    return executable;
  }

  static Map<String, String> _environmentOverrides({
    required String executable,
  }) {
    if (executable == 'flutter') {
      // If this ever changes we also need to update the `shorebird` shell
      // wrapper which downloads runs Flutter to fetch artifacts the first time.
      return {'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev/'};
    }

    return {};
  }
}

// coverage:ignore-start
@visibleForTesting
class ProcessWrapper {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    return Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
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
