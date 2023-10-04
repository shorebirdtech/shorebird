import 'dart:io';

import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [Git] instance.
final gitRef = create(Git.new);

/// The [Git] instance available in the current zone.
Git get git => read(gitRef);

/// A wrapper around all git related functionality.
class Git {
  static const executable = 'git';

  /// Clones the git repository located at [url] into the [outputDirectory].
  /// `git clone <url> ...<args> <outputDirectory>`
  Future<void> clone({
    required String url,
    required String outputDirectory,
    List<String>? args,
  }) async {
    final arguments = [
      'clone',
      url,
      ...?args,
      outputDirectory,
    ];
    final result = await process.run(
      executable,
      arguments,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// Checks out the git repository located at [directory] to the [revision].
  Future<void> checkout({
    required String directory,
    required String revision,
  }) async {
    final arguments = [
      '-C',
      directory,
      '-c',
      'advice.detachedHead=false',
      'checkout',
      revision,
    ];
    final result = await process.run(
      executable,
      arguments,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// Fetch branches/tags from the repository at [directory].
  Future<void> fetch({required String directory, List<String>? args}) async {
    final arguments = ['fetch', ...?args];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: directory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// Iterate over all refs that match [pattern] and show them
  /// according to the given [format].
  Future<String> forEachRef({
    required String directory,
    required String format,
    required String pattern,
    String? contains,
  }) async {
    final arguments = [
      'for-each-ref',
      if (contains != null) ...['--contains', contains],
      '--format',
      format,
      pattern,
    ];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: directory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }

  /// Resets the git repository located at [directory] to the [revision].
  Future<void> reset({
    required String revision,
    required String directory,
    List<String>? args,
  }) async {
    final arguments = ['reset', ...?args, revision];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: directory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  /// Returns the revision of the git repository located at [directory].
  Future<String> revParse({
    required String revision,
    required String directory,
  }) async {
    final arguments = ['rev-parse', '--verify', revision];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: directory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }

  /// Returns the status of the git repository located at [directory].
  Future<String> status({required String directory, List<String>? args}) async {
    final arguments = ['status', ...?args];
    final result = await process.run(
      executable,
      arguments,
      workingDirectory: directory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }
}
