import 'dart:io';

import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/logger.dart';

Future<void> main(List<String> args) async {
  await _flushThenExit(
    await runScoped(
      () async => ShorebirdCliCommandRunner().run(args),
      values: {authRef, loggerRef},
    ),
  );
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([stdout.close(), stderr.close()])
      .then<void>((_) => exit(status));
}
