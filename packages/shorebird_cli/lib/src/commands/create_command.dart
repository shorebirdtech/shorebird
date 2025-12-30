import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template shorebird_create_command}
/// `shorebird create`
/// Create a new Flutter app with Shorebird.
/// {@endtemplate}
class CreateCommand extends ShorebirdProxyCommand {
  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Flutter project with Shorebird.';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final createExitCode = await process.stream('flutter', [
      'create',
      ...results.rest,
    ]);

    if (createExitCode != ExitCode.success.code) {
      return createExitCode;
    }

    if (results.rest.contains('-h') || results.rest.contains('--help')) {
      return createExitCode;
    }

    return runScoped(
      () => runner!.run(['init']),
      values: {
        shorebirdEnvRef.overrideWith(
          () => ShorebirdEnv(
            flutterProjectRootOverride: p.absolute(
              p.normalize(results.rest.first),
            ),
          ),
        ),
      },
    );
  }
}
