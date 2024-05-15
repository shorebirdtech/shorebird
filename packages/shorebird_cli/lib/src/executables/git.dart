import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Git] instance.
final gitRef = create(Git.new);

/// The [Git] instance available in the current zone.
Git get git => read(gitRef);

/// A wrapper around all git related functionality.
class Git {
  static const executable = 'git';

  /// Execute a git command with the provided [arguments].
  Future<ShorebirdProcessResult> git(
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    final result = await process.run(
      executable,
      arguments,
      runInShell: runInShell,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
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
    await git(
      [
        'clone',
        url,
        ...?args,
        outputDirectory,
      ],
      runInShell: true,
    );
  }

  /// Checks out the git repository located at [directory] to the [revision].
  Future<void> checkout({
    required String directory,
    required String revision,
  }) async {
    await git(
      [
        '-C',
        directory,
        '-c',
        'advice.detachedHead=false',
        'checkout',
        revision,
      ],
      runInShell: true,
    );
  }

  /// Fetch branches/tags from the repository at [directory].
  Future<void> fetch({required String directory, List<String>? args}) async {
    await git(['fetch', ...?args], workingDirectory: directory);
  }

  /// Run `git remote` at [directory].
  Future<void> remote({
    required String directory,
    List<String>? args,
  }) async {
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
    final result = await git(
      [
        'for-each-ref',
        if (contains != null) ...['--contains', contains],
        '--format',
        format,
        pattern,
      ],
      workingDirectory: directory,
    );
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
    final result = await git(
      ['rev-parse', '--verify', revision],
      workingDirectory: directory,
    );
    return '${result.stdout}'.trim();
  }

  /// Returns the status of the git repository located at [directory].
  Future<String> status({required String directory, List<String>? args}) async {
    final result = await git(['status', ...?args], workingDirectory: directory);
    return '${result.stdout}'.trim();
  }
}
