import 'dart:io';

import 'package:cutler/config.dart';
import 'package:cutler/model.dart';
import 'package:path/path.dart' as p;

/// Our path constants.
enum Paths {
  engineDEPS('DEPS'),
  flutterEngineVersion('bin/internal/engine.version'),
  shorebirdFlutterVersion('bin/internal/flutter.version');

  const Paths(this.path);
  final String path;
}

String runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
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

  String get _workingDirectory => '${config.checkoutsRoot}/$path';

  String getLatestCommit(String branch) {
    return runCommand(
      'git',
      ['log', '-1', '--pretty=%H', branch],
      workingDirectory: _workingDirectory,
    );
  }

  List<String> getTagsFor(String commit) {
    final output = runCommand(
      'git',
      ['tag', '--points-at', commit],
      workingDirectory: _workingDirectory,
    );
    if (output.isEmpty) {
      return [];
    }
    return output.split('\n');
  }

  Version getForkPoint(String forkBranch) {
    final hash = runCommand(
      'git',
      ['merge-base', '--fork-point', upstreamBranch, forkBranch],
      workingDirectory: _workingDirectory,
    );
    return versionFrom(hash);
  }

  String contentsAtPath(String commit, String path) {
    return runCommand(
      'git',
      ['show', '$commit:$path'],
      workingDirectory: _workingDirectory,
    );
  }

  void writeFile(String path, String contents) {
    File(path).writeAsStringSync(contents);
  }

  void commit(String message) {
    runCommand(
      'git',
      ['commit', '-a', '-m', message],
      workingDirectory: _workingDirectory,
    );
  }

  Version localHead() {
    return versionFrom(
      runCommand(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: _workingDirectory,
      ),
    );
  }
}

extension VersionCommands on Version {
  String contentsAtPath(String path) {
    return repo.contentsAtPath(hash, path);
  }
}

String printLatestForBranch(Repo repo, String branch) {
  final hash = repo.getLatestCommit(branch);
  final tags = repo.getTagsFor(hash);
  final tagsString = tags.isEmpty ? '' : " (${tags.join(', ')})";
  print('${repo.name.padRight(10)} ${branch.padRight(25)} $hash$tagsString');
  return hash;
}

void printVersions(VersionSet versions, int indent) {
  print("${' ' * indent}flutter   ${versions.flutter}");
  print("${' ' * indent}engine    ${versions.engine}");
  print("${' ' * indent}buildroot ${versions.buildroot}");
}

VersionSet getFlutterVersions(String flutterHash) {
  final engineHash = Repo.flutter
      .contentsAtPath(flutterHash, 'bin/internal/engine.version')
      .trim();
  final depsContents =
      Repo.engine.contentsAtPath(engineHash, Paths.engineDEPS.path);
  final buildrootVersion = parseBuildRoot(depsContents);
  return VersionSet(
    engine: Repo.engine.versionFrom(engineHash),
    flutter: Repo.flutter.versionFrom(flutterHash),
    buildroot: Repo.buildroot.versionFrom(buildrootVersion),
  );
}

String parseBuildRoot(String depsContents) {
  final lines = depsContents.split('\n');
  // Example:
  //   'src': 'https://github.com/flutter/buildroot.git' + '@' + '059d155b4d452efd9c4427c45cddfd9445144869',
  final buildrootLine = lines.firstWhere((line) => line.contains("'src': "));
  final regexp = RegExp('([0-9a-f]{40})');
  final match = regexp.firstMatch(buildrootLine);
  if (match == null) {
    throw Exception('Failed to parse buildroot version from $buildrootLine');
  }
  return match.group(0)!;
}

/// Generate rebase commands for the repo given the version sets.
String rebaseRepo(
  Repo repo, {
  required VersionSet forkpoints,
  required VersionSet upstream,
  required VersionSet shorebird,
  bool dryRun = true,
}) {
  final run = dryRun ? dryRunCommand : runCommand;
  if (upstream[repo] != forkpoints[repo]) {
    print('Rebasing ${repo.name}...');
    run(
      'git',
      [
        'rebase',
        '--onto',
        upstream[repo].ref,
        forkpoints[repo].ref,
        shorebird[repo].ref
      ],
      workingDirectory: repo._workingDirectory,
    );

    return dryRun ? 'new-${repo.name}-hash' : repo.getLatestCommit('HEAD');
  } else {
    print('Skipping ${repo.name} (unchanged: ${upstream[repo].ref})');
  }
  return shorebird[repo].ref;
}

/// Cutler will always try to upgrade to the latest flutter version
/// on the stable branch.
void main(List<String> args) {
  config = parseArgs(args);
  if (config.doUpdate) {
    print('Updating checkouts (use --no-update to skip)');
    for (final repo in Repo.values) {
      print('Updating ${repo.name}...');
      runCommand(
        'git',
        ['fetch', '--all'],
        workingDirectory: repo._workingDirectory,
      );
    }
  }
  // This prints the latest versions on our branches, not necessarily
  // the ones shorebird depends on.
  // for (final repo in Repo.values) {
  //   printLatestForBranch(repo, repo.releaseBranch);
  // }

  final shorebirdStable =
      Repo.shorebird.getLatestCommit(config.shorebirdReleaseBranch);
  final shorebirdFlutter = Repo.shorebird
      .contentsAtPath(shorebirdStable, 'bin/internal/flutter.version');
  final shorebird = getFlutterVersions(shorebirdFlutter);
  print('Shorebird stable:');
  printVersions(shorebird, 2);

  final flutterForkpoint = Repo.flutter.getForkPoint(shorebird.flutter.hash);
  // This is slightly error-prone in that we're assuming that our engine and
  // buildroot forks started from the correct commit.  But I'm not sure how
  // to determine the forkpoint otherwise.  engine and buildroot don't have
  // a stable branch, yet they do seem to "branch" for stable releases at the
  // x.x.0 release.
  final forkpoints = getFlutterVersions(flutterForkpoint.hash);
  print('Forkpoints:');
  printVersions(forkpoints, 2);

  // Figure out the latest version of Flutter.
  final upstreamFlutter =
      Repo.flutter.getLatestCommit('upstream/${config.flutterChannel}');
  // Figure out what versions that Flutter depends on.
  final upstream = getFlutterVersions(upstreamFlutter);
  print('Upstream ${config.flutterChannel}:');
  printVersions(upstream, 2);

  Version doRebase(Repo repo) {
    final newHash = rebaseRepo(
      repo,
      forkpoints: forkpoints,
      upstream: upstream,
      shorebird: shorebird,
      dryRun: config.dryRun,
    );
    return repo.versionFrom(newHash, lookupTags: !config.dryRun);
  }

  // Rebase our repos.
  var newHead = VersionSet(
    buildroot: doRebase(Repo.buildroot),
    engine: doRebase(Repo.engine),
    flutter: doRebase(Repo.flutter),
  );
  // Make sure engine points to this buildroot.
  // If not, update it and commit.
  if (shorebird[Repo.buildroot] != newHead.buildroot) {
    print('Updating engine DEPS...');
    final depsContents =
        shorebird[Repo.engine].contentsAtPath(Paths.engineDEPS.path);
    final newDepsContents = depsContents.replaceAll(
      shorebird[Repo.buildroot].hash,
      newHead.buildroot.hash,
    );
    if (newDepsContents != depsContents) {
      if (config.dryRun) {
        print('Would have changed DEPS lines:');
        final changes = newDepsContents.split('\n').where((line) {
          return line.contains(newHead.buildroot.hash);
        });
        print(changes);
      } else {
        Repo.engine.writeFile(Paths.engineDEPS.path, newDepsContents);
        Repo.engine.commit('Update DEPS.');
      }
    } else {
      print('ERROR: engine DEPS is already up to date?');
      exit(1);
    }
    newHead = newHead.copyWith(engine: Repo.engine.localHead());
  }

  // Update our forked flutter's engine version.
  if (shorebird[Repo.engine] != newHead.engine) {
    print('Updating flutter engine version...');
    final existingEngineVersion = shorebird[Repo.flutter]
        .contentsAtPath(Paths.flutterEngineVersion.path)
        .trim();
    if (newHead.engine.hash != existingEngineVersion) {
      if (config.dryRun) {
        print(
          '  Change engine.version: ${newHead.engine.hash} from '
          '$existingEngineVersion',
        );
      } else {
        Repo.flutter
            .writeFile(Paths.flutterEngineVersion.path, newHead.engine.hash);
        Repo.flutter.commit('Update engine.version');
      }
    } else {
      print('ERROR: flutter engine.version is already up to date?');
      exit(1);
    }
    newHead = newHead.copyWith(flutter: Repo.flutter.localHead());
  }
  // Update Shorebird's version of Flutter.
  if (shorebird[Repo.flutter] != newHead.flutter) {
    print('Updating shorebird flutter version...');
    if (config.dryRun) {
      print(
        '  Change flutter.version: ${newHead.flutter.hash} from '
        '${shorebird[Repo.flutter].hash}',
      );
    } else {
      Repo.shorebird
          .writeFile(Paths.shorebirdFlutterVersion.path, newHead.flutter.hash);
      Repo.shorebird.commit('Update flutter.version');
    }
  }

  // To push a new engine:
  // git branch stable_codepush HEAD --force
  // git push origin stable_codepush --force

  // Engine rev: d470ae25d21f583abe128f7b838476afd5e45bde

  // To push new flutter:
  // % git rebase --onto 3.7.12 3.7.10 \
  // 45fc514f1a9c347a3af76b02baf980a4d88b7879
  // Auto-merging bin/internal/engine.version
  // CONFLICT (content): Merge conflict in bin/internal/engine.version
  // error: could not apply c2185f5f6c... chore: Update engine version to
  // shorebird-3.7.10
  // hint: Resolve all conflicts manually, mark them as resolved with
  // hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
  // hint: You can instead skip this commit: run "git rebase --skip".
  // hint: To abort and get back to the state before "git rebase", run "git
  // rebase --abort".
  // Could not apply c2185f5f6c... chore: Update engine version to
  // shorebird-3.7.10

  // Flutter revision: 58dff390738f9c512ab7e0638af9573515b0409c

  // To push new shorebird:
}
