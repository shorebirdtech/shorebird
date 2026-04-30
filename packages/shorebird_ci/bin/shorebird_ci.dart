import 'dart:io';

import 'package:shorebird_ci/src/shorebird_ci_command_runner.dart';

Future<void> main(List<String> args) async {
  exit(await ShorebirdCiCommandRunner().run(args) ?? 0);
}
