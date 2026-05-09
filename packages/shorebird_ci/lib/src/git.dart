import 'dart:io';

/// Runs git commands via [Process.runSync].
///
/// All calls are synchronous. We never run multiple git commands in
/// parallel and Dart's sync IO is faster than its async IO when you're
/// just going to await the result anyway.
class Git {
  /// Creates a [Git] instance.
  const Git();

  /// Returns the list of files changed between [base] and [head].
  List<String> changedFiles({
    required String base,
    required String head,
    required String workingDirectory,
  }) {
    final args = ['diff', '--name-only', base, head];
    final result = Process.runSync(
      'git',
      args,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException('git', args, '${result.stderr}', result.exitCode);
    }
    return (result.stdout as String)
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Returns the paths of all git submodules.
  List<String> submodulePaths({required String workingDirectory}) {
    final result = Process.runSync(
      'git',
      ['submodule', 'status'],
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) return [];
    return parseSubmoduleStatus(result.stdout as String);
  }

  /// Returns whether the given [path] is ignored by git.
  bool isIgnored({required String path, required String workingDirectory}) {
    final result = Process.runSync(
      'git',
      ['check-ignore', '-q', path],
      workingDirectory: workingDirectory,
    );
    return result.exitCode == 0;
  }
}

/// Parses the output of `git submodule status` and returns the
/// submodule paths.
///
/// Each non-empty line has the form:
/// ```text
///   <flag><sha> <path>[ (<describe-output>)]
/// ```
/// where `<flag>` is one of space (initialized), `-` (uninitialized),
/// `+` (commit doesn't match index), `U` (merge conflicts).
/// `<path>` may contain spaces. `(<describe-output>)` is optional and
/// only present when the submodule is initialized.
List<String> parseSubmoduleStatus(String output) {
  // Match the leading flag + SHA, capture the path, then strip an
  // optional trailing ` (...)` describe-output. Captures everything
  // between the SHA and the optional ` (` so paths with spaces work.
  final lineRe = RegExp(r'^[ +\-U][0-9a-f]+\s+(.+?)(?:\s+\([^)]*\))?$');
  return output
      .split('\n')
      .where((line) => line.isNotEmpty)
      .map((line) => lineRe.firstMatch(line)?.group(1))
      .whereType<String>()
      .toList();
}
