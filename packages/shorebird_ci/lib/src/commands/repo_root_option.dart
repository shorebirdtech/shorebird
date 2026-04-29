import 'package:args/command_runner.dart';

/// Adds a `--repo-root` option to a command and exposes it via
/// [repoRoot]. Default is `'.'` to match the convention used by every
/// other command in this package.
mixin RepoRootOption on Command<int> {
  /// Call from the command's constructor to register the option.
  void addRepoRootOption() {
    argParser.addOption(
      'repo-root',
      help: 'Path to the repository root.',
    );
  }

  /// The resolved repo root, or `'.'` if not specified.
  String get repoRoot => argResults!['repo-root'] as String? ?? '.';
}
