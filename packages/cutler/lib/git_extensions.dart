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

void dryRunCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  print("$executable ${arguments.join(' ')}");
}

extension RepoCommands on Repo {
  Version versionFrom(String hash, {bool lookupTags = true}) {
    return Version(
      hash: hash,
      repo: this,
      aliases: lookupTags ? getTagsFor(hash) : [],
    );
  }

  String get workingDirectory => '${config.checkoutsRoot}/$path';

  String getLatestCommit(String branch) {
    return runCommand(
      'git',
      ['log', '-1', '--pretty=%H', branch],
      workingDirectory: workingDirectory,
    );
  }

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

  Version getForkPoint(String forkBranch) {
    final hash = runCommand(
      'git',
      ['merge-base', upstreamBranch, forkBranch],
      workingDirectory: workingDirectory,
    );
    return versionFrom(hash);
  }

  String contentsAtPath(String commit, String path) {
    return runCommand(
      'git',
      ['show', '$commit:$path'],
      workingDirectory: workingDirectory,
    );
  }

  void writeFile(String path, String contents) {
    File(path).writeAsStringSync(contents);
  }

  void commit(String message) {
    runCommand(
      'git',
      ['commit', '-a', '-m', message],
      workingDirectory: workingDirectory,
    );
  }

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

extension VersionCommands on Version {
  String contentsAtPath(String path) {
    return repo.contentsAtPath(hash, path);
  }
}
