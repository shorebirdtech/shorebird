import 'dart:io';

import 'package:cutler/config.dart';
import 'package:cutler/model.dart';
import 'package:path/path.dart' as p;

/// This file provides the git extensions to our model objects for Cutler.
/// That lets the models be pure data objects, and keeps the command-running
/// code separate.  Unsure if this is a good design or not.

String runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  if (workingDirectory != null && !Directory(workingDirectory).existsSync()) {
    throw Exception('Directory $workingDirectory does not exist.');
  }

  if (config.verbose) {
    final workingDirectoryString = workingDirectory == null ||
            p.equals(workingDirectory, Directory.current.path)
        ? ''
        : ' (in $workingDirectory)';
    print("$executable ${arguments.join(' ')}$workingDirectoryString");
  }
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to run $executable $arguments: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

/// Function to print the command that would be run, but not actually run it.
void dryRunCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  print("$executable ${arguments.join(' ')}");
}

/// Extension methods for [Repo] to do actual `git` actions.
extension RepoCommands on Repo {
  /// Returns a [Version] for the given [hash].
  Version versionFrom(String hash, {bool lookupTags = true}) {
    return Version(
      hash: hash,
      repo: this,
      aliases: lookupTags ? getTagsFor(hash) : [],
    );
  }

  /// Returns the working directory for this repo.
  String get workingDirectory => '${config.checkoutsRoot}/$path';

  /// Returns the latest commit for a given [branch] in this repo.
  String getLatestCommit(String branch) {
    return runCommand(
      'git',
      ['log', '-1', '--pretty=%H', branch],
      workingDirectory: workingDirectory,
    );
  }

  /// Returns the tags for a given [commit] in this repo.
  List<String> getTagsFor(String commit) {
    final output = runCommand(
      'git',
      ['tag', '--points-at', commit],
      workingDirectory: workingDirectory,
    );
    if (output.isEmpty) {
      return [];
    }
    return output.split('\n');
  }

  /// Returns the fork point as a [Version] for this repo given a [forkBranch].
  Version getForkPoint(String forkBranch) {
    final hash = runCommand(
      'git',
      ['merge-base', upstreamBranch, forkBranch],
      workingDirectory: workingDirectory,
    );
    return versionFrom(hash);
  }

  /// Returns the contents of a file at a given [path] in this repo at a given
  /// [commit].
  String contentsAtPath(String commit, String path) {
    return runCommand(
      'git',
      ['show', '$commit:$path'],
      workingDirectory: workingDirectory,
    );
  }

  /// Writes [contents] to a file at a given [path] in this repo.
  void writeFile(String path, String contents) {
    File(path).writeAsStringSync(contents);
  }

  /// Commits to this repo with a given [message].
  void commit(String message) {
    runCommand(
      'git',
      ['commit', '-a', '-m', message],
      workingDirectory: workingDirectory,
    );
  }

  /// Returns a [Version] object representing the current HEAD of this repo.
  Version localHead() {
    return versionFrom(
      runCommand(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: workingDirectory,
      ),
    );
  }
}

/// Extension methods for [Version] to do actual `git` actions.
extension VersionCommands on Version {
  /// Returns the contents of a file at a given [path] in this repo at this
  /// version.
  String contentsAtPath(String path) {
    return repo.contentsAtPath(hash, path);
  }
}
