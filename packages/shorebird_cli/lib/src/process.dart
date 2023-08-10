import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

// A reference to a [EngineConfig] instance.
final engineConfigRef = create(() => const EngineConfig.empty());

// The [EngineConfig] instance available in the current zone.
EngineConfig get engineConfig => read(engineConfigRef);

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
    this.engineConfig = const EngineConfig.empty(),
    Logger? logger,
    ProcessWrapper? processWrapper, // For mocking ShorebirdProcess.
  })  : logger = logger ?? Logger(),
        processWrapper = processWrapper ?? const ProcessWrapper();

  final ProcessWrapper processWrapper;
  final EngineConfig engineConfig;
  final Logger logger;

  Future<ShorebirdProcessResult> run(
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

    final resolvedExecutable =
        useVendedFlutter ? _resolveExecutable(executable) : executable;
    final resolvedArguments =
        useVendedFlutter ? _resolveArguments(executable, arguments) : arguments;
    logger.detail(
      '''[Process.run] $resolvedExecutable ${resolvedArguments.join(' ')}${workingDirectory == null ? '' : ' (in $workingDirectory)'}''',
    );

    return processWrapper.run(
      resolvedExecutable,
      resolvedArguments,
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
    final resolvedExecutable =
        useVendedFlutter ? _resolveExecutable(executable) : executable;
    final resolvedArguments =
        useVendedFlutter ? _resolveArguments(executable, arguments) : arguments;
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

  String _resolveExecutable(String executable) {
    if (executable == 'flutter') return shorebirdEnv.flutterBinaryFile.path;
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
        ...arguments,
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
  const ProcessWrapper();

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
