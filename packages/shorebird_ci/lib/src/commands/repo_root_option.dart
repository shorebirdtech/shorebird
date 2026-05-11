import 'dart:io';

import 'package:args/command_runner.dart';

/// Adds a `--repo-root` option to a command and exposes it via
/// [repoRoot].
///
/// When `--repo-root` is not provided, the value is auto-discovered via
/// `git rev-parse --show-toplevel`, so commands work from any
/// subdirectory of a git checkout — same convention as `git` itself.
/// Falls back to `'.'` if git is unavailable or the cwd is not inside a
/// git repo.
mixin RepoRootOption on Command<int> {
  /// Call from the command's constructor to register the option.
  void addRepoRootOption() {
    argParser.addOption(
      'repo-root',
      help:
          'Path to the repository root. '
          'Defaults to the output of `git rev-parse --show-toplevel`.',
    );
  }

  /// The resolved repo root.
  String get repoRoot {
    final explicit = argResults!['repo-root'] as String?;
    if (explicit != null) return explicit;
    final result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
    if (result.exitCode == 0) {
      final stdout = (result.stdout as String).trim();
      if (stdout.isNotEmpty) return stdout;
    }
    return '.';
  }
}
