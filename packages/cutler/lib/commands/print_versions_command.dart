import 'package:cutler/commands/base.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

class PrintVersionsCommand extends CutlerCommand {
  PrintVersionsCommand({required super.logger});
  @override
  final name = 'print-versions';
  @override
  final description =
      'Print the versions a given Shorebird release hash depends on.';

  @override
  int run() {
    late final String shorebirdHash;
    if (argResults!.rest.isEmpty) {
      print('No Shorebird hash provided, using `origin/stable`.');
      shorebirdHash = 'origin/stable';
    } else {
      shorebirdHash = argResults!.rest.first;
    }

    final shorebirdFlutter = Repo.shorebird
        .contentsAtPath(shorebirdHash, 'bin/internal/flutter.version');
    final shorebird = getFlutterVersions(shorebirdFlutter);
    print('Shorebird $shorebirdHash:');
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

    return ExitCode.success.code;
  }
}
