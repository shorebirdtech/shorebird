import 'package:args/command_runner.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

class PrintVersionsCommand extends Command<int> {
  PrintVersionsCommand();
  @override
  final name = 'print-versions';
  @override
  final description =
      'Print the versions a given Shorebird release hash depends on.';

  @override
  int run() {
    final shorebirdHash = argResults!.rest.first;
    final shorebirdFlutter = Repo.shorebird
        .contentsAtPath(shorebirdHash, 'bin/internal/flutter.version');
    final shorebird = getFlutterVersions(shorebirdFlutter);
    print('Shorebird $shorebirdHash:');
    printVersions(shorebird, 2);
    return ExitCode.success.code;
  }
}
