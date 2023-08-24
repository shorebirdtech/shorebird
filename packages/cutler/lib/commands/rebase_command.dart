import 'package:cutler/commands/base.dart';
import 'package:cutler/config.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

/// Prints the latest commit for a given [branch] in a given [repo].
String printLatestForBranch(Repo repo, String branch) {
  final hash = repo.getLatestCommit(branch);
  final tags = repo.getTagsFor(hash);
  final tagsString = tags.isEmpty ? '' : " (${tags.join(', ')})";
  print('${repo.name.padRight(10)} ${branch.padRight(25)} $hash$tagsString');
  return hash;
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
        shorebird[repo].ref,
      ],
      workingDirectory: repo.workingDirectory,
    );

    return dryRun ? 'new-${repo.name}-hash' : repo.getLatestCommit('HEAD');
  } else {
    print('Skipping ${repo.name} (unchanged: ${upstream[repo].ref})');
  }
  return shorebird[repo].ref;
}

/// Print the commands needed to rebase our repos onto the given Flutter
/// revision.
class RebaseCommand extends CutlerCommand {
  /// Constructs a new [RebaseCommand] with a given [logger].
  RebaseCommand({required super.logger});
  @override
  final name = 'rebase';
  @override
  final description = 'Rebase our repos onto the latest Flutter.';

  @override
  int run() {
    updateReposIfNeeded(config);

    final shorebirdStable =
        Repo.shorebird.getLatestCommit(config.shorebirdReleaseBranch);
    final shorebirdFlutter = Repo.shorebird
        .contentsAtPath(shorebirdStable, 'bin/internal/flutter.version');
    final shorebird = getFlutterVersions(shorebirdFlutter);
    print('Shorebird stable:');
    printVersions(shorebird, indent: 2);

    final flutterForkpoint = Repo.flutter.getForkPoint(shorebird.flutter.hash);
    // This is slightly error-prone in that we're assuming that our engine and
    // buildroot forks started from the correct commit.  But I'm not sure how
    // to determine the forkpoint otherwise.  engine and buildroot don't have
    // a stable branch, yet they do seem to "branch" for stable releases at the
    // x.x.0 release.
    final forkpoints = getFlutterVersions(flutterForkpoint.hash);
    print('Forkpoints:');
    printVersions(forkpoints, indent: 2);

    // Figure out the latest version of Flutter.
    final upstreamFlutter =
        Repo.flutter.getLatestCommit('upstream/${config.flutterChannel}');
    // Figure out what versions that Flutter depends on.
    final upstream = getFlutterVersions(upstreamFlutter);
    print('Upstream ${config.flutterChannel}:');
    printVersions(upstream, indent: 2);

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
    // These are done in a very specific order.
    var newHead = VersionSet(
      buildroot: doRebase(Repo.buildroot),
      dart: doRebase(Repo.dart),
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
        return ExitCode.software.code;
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
        return ExitCode.software.code;
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
        Repo.shorebird.writeFile(
          Paths.shorebirdFlutterVersion.path,
          newHead.flutter.hash,
        );
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
    return ExitCode.success.code;
  }
}
