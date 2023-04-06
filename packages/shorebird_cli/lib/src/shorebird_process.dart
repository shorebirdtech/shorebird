import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/shorebird_paths.dart';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
  String? workingDirectory,
  bool resolveExecutables,
});

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
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
    String? workingDirectory,
    bool resolveExecutables = true,
  }) {
    return processWrapper.run(
      resolveExecutables ? _resolveExecutable(executable) : executable,
      arguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
    );
  }

  static Future<Process> start(
    String executable,
    List<String> argument, {
    bool runInShell = false,
    bool resolveExecutables = true,
  }) {
    return processWrapper.start(
      resolveExecutables ? _resolveExecutable(executable) : executable,
      argument,
      runInShell: runInShell,
    );
  }

  static String _resolveExecutable(String executable) {
    if (executable == 'flutter') {
      return ShorebirdPaths.flutterBinaryFile.path;
    }

    return executable;
  }
}

// coverage:ignore-start
@visibleForTesting
class ProcessWrapper {
  RunProcess get run => (
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        String? workingDirectory,
        bool resolveExecutables = true,
      }) =>
          Process.run(
            executable,
            arguments,
            runInShell: runInShell,
            workingDirectory: workingDirectory,
          );

  StartProcess get start => Process.start;
}
// coverage:ignore-end
