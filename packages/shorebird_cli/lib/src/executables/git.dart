// cspell:words unmatch
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Git] instance.
final gitRef = create(Git.new);

/// The [Git] instance available in the current zone.
Git get git => read(gitRef);

/// {@template github_outage_exception}
/// Exception thrown when a git command fails due to a GitHub outage.
/// {@endtemplate}
class GitHubOutageException implements Exception {
  /// {@macro github_outage_exception}
  const GitHubOutageException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}

/// Pattern that matches GitHub HTTP server errors (500, 502, 503) in git
/// output.
final _githubOutagePattern = RegExp(
  'The requested URL returned error: (500|502|503)|Internal Server Error',
);

/// A wrapper around all git related functionality.
class Git {
  /// Name of the git executable.
  static const executable = 'git';

  /// Execute a git command with the provided [arguments].
  Future<ShorebirdProcessResult> git(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      final stderr = '${result.stderr}';
      // This assumes all git remotes are on GitHub, which is currently true
      // (we only clone/fetch shorebirdtech/flutter and shorebirdtech/shorebird).
      // If we ever add non-GitHub remotes, this detection should be scoped to
      // GitHub URLs only.
      if (_githubOutagePattern.hasMatch(stderr)) {
        throw const GitHubOutageException(
          'GitHub appears to be experiencing an outage. '
          'Please check https://www.githubstatus.com and try again later.',
        );
      }
      throw ProcessException(
        executable,
        arguments,
        stderr,
        result.exitCode,
      );
    }
    return result;
  }

  /// Clones the git repository located at [url] into the [outputDirectory].
  /// `git clone <url> ...<args> <outputDirectory>`
  Future<void> clone({
    required String url,
    required String outputDirectory,
    List<String>? args,
  }) async {
    await git(['clone', url, ...?args, outputDirectory]);
  }

  /// Checks out the git repository located at [directory] to the [revision].
  Future<void> checkout({
    required String directory,
    required String revision,
  }) async {
    await git([
      '-C',
      directory,
      '-c',
      'advice.detachedHead=false',
      'checkout',
      revision,
    ]);
  }

  /// Fetch branches/tags from the repository at [directory].
  Future<void> fetch({required String directory, List<String>? args}) async {
    await git(['fetch', ...?args], workingDirectory: directory);
  }

  /// Run `git remote` at [directory].
  Future<void> remote({required String directory, List<String>? args}) async {
    await git(['remote', ...?args], workingDirectory: directory);
  }

  /// Iterate over all refs that match [pattern] and show them
  /// according to the given [format].
  Future<String> forEachRef({
    required String directory,
    required String format,
    required String pattern,
    String? contains,
  }) async {
    final result = await git([
      'for-each-ref',
      if (contains != null) ...['--contains', contains],
      '--format',
      format,
      pattern,
    ], workingDirectory: directory);
    return '${result.stdout}'.trim();
  }

  /// Resets the git repository located at [directory] to the [revision].
  Future<void> reset({
    required String revision,
    required String directory,
    List<String>? args,
  }) async {
    await git(['reset', ...?args, revision], workingDirectory: directory);
  }

  /// Returns the revision of the git repository located at [directory].
  Future<String> revParse({
    required String revision,
    required String directory,
  }) async {
    final result = await git([
      'rev-parse',
      '--verify',
      revision,
    ], workingDirectory: directory);
    return '${result.stdout}'.trim();
  }

  /// Returns the status of the git repository located at [directory].
  Future<String> status({required String directory, List<String>? args}) async {
    final result = await git(['status', ...?args], workingDirectory: directory);
    return '${result.stdout}'.trim();
  }

  /// The output of `git symbolic-ref [revision]` for the git repository located
  /// in [directory]. If not provided, [revision] defaults to 'HEAD'.
  Future<String> symbolicRef({
    required Directory directory,
    String revision = 'HEAD',
  }) async {
    final result = await git([
      'symbolic-ref',
      revision,
    ], workingDirectory: directory.path);
    return '${result.stdout}'.trim();
  }

  /// Returns the name of the branch the git repository located at [directory]
  /// is currently on.
  Future<String> currentBranch({required Directory directory}) async {
    return (await symbolicRef(
      directory: directory,
    )).replaceAll('refs/heads/', '');
  }

  /// Whether [directory] is part of a git repository.
  Future<bool> isGitRepo({required Directory directory}) async {
    try {
      // [git] throws if the command's exit code is nonzero, which is what we're
      // checking for here.
      await git(['status'], workingDirectory: directory.path);
    } on Exception {
      return false;
    }

    return true;
  }

  /// Whether [file] is tracked by its git repository.
  Future<bool> isFileTracked({required File file}) async {
    try {
      // [git] throws if the command's exit code is nonzero, which is what we're
      // checking for here.
      await git([
        'ls-files',
        '--error-unmatch',
        file.absolute.path,
      ], workingDirectory: file.parent.path);
    } on Exception {
      return false;
    }

    return true;
  }
}
