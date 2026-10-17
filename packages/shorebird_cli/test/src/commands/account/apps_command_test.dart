import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/account/apps_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountAppsCommand, () {
    late ShorebirdLogger logger;
    late AccountAppsCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
      command = AccountAppsCommand();
    });

    test('is hidden and names its replacement', () {
      expect(command.hidden, isTrue);
      expect(command.description, contains('shorebird apps list'));
    });

    test('prints the replacement and exits with a usage error', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err(
          '`shorebird account apps` has moved to `shorebird apps list`.',
        ),
      ).called(1);
      verify(() => logger.info('Run: shorebird apps list')).called(1);
    });

    test('emits a usage error envelope with --json', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.usage.code));
      expect(json['error'], {
        'code': 'usage_error',
        'message':
            '`shorebird account apps` has moved to `shorebird apps list`.',
        'hint': 'Run: shorebird apps list',
      });
    });
  });
}
