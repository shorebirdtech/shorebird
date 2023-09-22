import 'dart:io';

import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:path/path.dart' as p;

/// This file provides the git extensions to our model objects for Cutler.
/// That lets the models be pure data objects, and keeps the command-running
/// code separate.  Unsure if this is a good design or not.

/// Runs a command and returns the result.
ProcessResult runCommandInner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  if (workingDirectory != null && !Directory(workingDirectory).existsSync()) {
    throw Exception('Directory $workingDirectory does not exist.');
  }

  final workingDirectoryString = workingDirectory == null ||
          p.equals(workingDirectory, Directory.current.path)
      ? ''
      : ' (in $workingDirectory)';
  logger.detail("$executable ${arguments.join(' ')}$workingDirectoryString");

  return Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}

/// Runs a command and returns stdout, trimmed.
String runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  final result = runCommandInner(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to run $executable $arguments: ${result.stdout} ${result.stderr}',
    );
  }
  return result.stdout.toString().trim();
}

/// Represents all the checkouts cutler knows about.
class Checkouts {
  /// Constructs a new [Checkouts] object with a given [root] directory.
  Checkouts(this.root) {
    for (final repo in Repo.values) {
      _checkouts[repo] = Checkout(repo, root);
    }
  }

  /// The root directory for all checkouts.
  final String root;

  /// The checkouts.
  final _checkouts = <Repo, Checkout>{};

  /// Returns an iterable of all checkouts.
  Iterable<Checkout> get values => _checkouts.values;

  /// Returns a [Checkout] for a given [repo].
  Checkout operator [](Repo repo) => _checkouts[repo]!;

  /// Returns a [Checkout] for Flutter.
  Checkout get flutter => _checkouts[Repo.flutter]!;

  /// Returns a [Checkout] for Engine.
  Checkout get engine => _checkouts[Repo.engine]!;

  /// Returns a [Checkout] for Dart.
  Checkout get dart => _checkouts[Repo.dart]!;

  /// Returns a [Checkout] for Buildroot.
  Checkout get buildroot => _checkouts[Repo.buildroot]!;

  /// Returns a [Checkout] for Shorebird.
  Checkout get shorebird => _checkouts[Repo.shorebird]!;
}

/// Extension methods for [Repo] to do actual `git` actions.
class Checkout {
  /// Constructs a new [Checkout] for a given [repo].
  Checkout(this.repo, String checkoutsRoot) : _checkoutsRoot = checkoutsRoot;

  /// The repo this checkout is for.
  final Repo repo;

  /// The root directory for all checkouts.
  final String _checkoutsRoot;

  /// The name of this repo.
  String get name => repo.name;

  /// Updates this repo.
  void fetchAll() {
    runCommand(
      'git',
      ['fetch', '--all', '--tags'],
      workingDirectory: workingDirectory,
    );
  }

  /// Returns a [Version] for the given [commitish].
  Version versionFrom(String commitish, {bool lookupTags = true}) {
    final hash = runCommand(
      'git',
      ['rev-parse', commitish],
      workingDirectory: workingDirectory,
    );
    return Version(
      hash: hash,
      repo: repo,
      aliases: lookupTags ? getTagsFor(hash) : [],
    );
  }

  /// Returns a [Version] for the given [branch] in the given [remote].
  Version remoteBranch({required String branch, required String remote}) {
    final output = runCommand(
      'git',
      ['ls-remote', '--refs', remote, branch],
      workingDirectory: workingDirectory,
    );
    final hash = output.split('\t').first;
    final name = output.split('\t').last;
    return Version(
      hash: hash,
      repo: repo,
      aliases: [name],
    );
  }

  /// Returns a [Version] for the given [tag] in the given [remote].
  Version remoteTag({
    required String remote,
    required String tag,
  }) {
    final tags = remoteTags(remote: remote, pattern: tag);
    if (tags.isEmpty) {
      throw Exception('No tags found for $tag in $remote');
    }
    if (tags.length > 1) {
      throw Exception('Multiple tags found for $tag in $remote');
    }
    return tags.first;
  }

  /// Returns a list of Versions for the given [pattern] in the given [remote].
  Iterable<Version> remoteTags({
    required String remote,
    String? pattern,
  }) {
    final args = ['ls-remote', '--tags', remote];
    if (pattern != null) {
      args.add(pattern);
    }
    final output = runCommand('git', args, workingDirectory: workingDirectory);
    // split lines
    final lines = output.split('\n');
    return lines.map<Version>((line) {
      final hash = line.split('\t').first;
      final name = line.split('\t').last;
      return Version(
        hash: hash,
        repo: repo,
        aliases: [name],
      );
    });
  }

  /// Returns true if [ancestor] is an ancestor of [descendant] in this repo.
  bool isAncestor({required String ancestor, required String descendant}) {
    final result = runCommandInner(
      'git',
      ['merge-base', '--is-ancestor', ancestor, descendant],
      workingDirectory: workingDirectory,
    );
    return result.exitCode == 0;
  }

  /// Returns a count of commits between two commits in this repo.
  int countCommits({required String from, required String to}) {
    final output = runCommand(
      'git',
      ['rev-list', '--count', '$from..$to'],
      workingDirectory: workingDirectory,
    );
    return int.parse(output);
  }

  /// Returns the working directory for this repo.
  String get workingDirectory => '$_checkoutsRoot/${repo.path}';

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
    final describeString = runCommand(
      'git',
      ['describe', '--tags', forkBranch],
      workingDirectory: workingDirectory,
    );
    final tag = describeString.split('-').first;
    return versionFrom(tag);
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
    File(p.join(workingDirectory, path)).writeAsStringSync(contents);
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
