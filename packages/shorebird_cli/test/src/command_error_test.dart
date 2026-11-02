import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(CommandError, () {
    test('is a usage error by default', () {
      final error = CommandError(message: 'Something is wrong.');
      expect(error.exitCode, equals(ExitCode.usage.code));
      expect(error.code, equals(JsonErrorCode.usageError));
      expect(error.hint, isNull);
    });

    test('reports another exit code as process_exit', () {
      final error = CommandError(
        message: 'The build failed.',
        exitCode: ExitCode.software,
      );
      expect(error.exitCode, equals(ExitCode.software.code));
      expect(error.code, equals(JsonErrorCode.processExit));
    });

    test('keeps an explicit code', () {
      final error = CommandError(
        message: 'The fetch failed.',
        exitCode: ExitCode.software,
        code: JsonErrorCode.fetchFailed,
      );
      expect(error.code, equals(JsonErrorCode.fetchFailed));
    });

    test('toString is its message', () {
      expect(
        CommandError(message: 'Something is wrong.').toString(),
        equals('Something is wrong.'),
      );
    });
  });
}
