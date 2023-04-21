import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

class EngineConfig {
  const EngineConfig({
    required this.localEngineSrcPath,
    required this.localEngine,
  });

  const EngineConfig.empty()
      : localEngineSrcPath = null,
        localEngine = null;

  final String? localEngineSrcPath;
  final String? localEngine;
}

/// A wrapper around [Process] that replaces executables to Shorebird-vended
/// versions.
// This may need a better name, since it returns "Process" it's more a
// "ProcessFactory" than a "Process".
class ShorebirdProcess {
  ShorebirdProcess({
    required this.engineConfig,
    ProcessWrapper? processWrapper, // For mocking ShorebirdProcess.
  }) : processWrapper = processWrapper ?? ProcessWrapper();

  final ProcessWrapper processWrapper;
  final EngineConfig engineConfig;

  Future<ProcessResult> run(
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
      useVendedFlutter ? _resolveArguments(executable, arguments) : arguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
      environment: resolvedEnvironment,
    );
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

    return processWrapper.start(
      useVendedFlutter ? _resolveExecutable(executable) : executable,
      useVendedFlutter ? _resolveArguments(executable, arguments) : arguments,
      runInShell: runInShell,
      environment: resolvedEnvironment,
    );
  }

  String _resolveExecutable(String executable) {
    if (executable == 'flutter') {
      return ShorebirdEnvironment.flutterBinaryFile.path;
    }

    return executable;
  }

  List<String> _resolveArguments(
    String executable,
    List<String> arguments,
  ) {
    if (executable == 'flutter' && engineConfig.localEngine != null) {
      return [
        '--local-engine-src-path=${engineConfig.localEngineSrcPath}',
        '--local-engine=${engineConfig.localEngine}',
        ...arguments
      ];
    }
    return arguments;
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
