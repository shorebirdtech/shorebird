import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/auth/auth.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AuthTokenCommand, () {
    final expiresAt = DateTime.utc(2026, 10, 17, 1);

    late ArgResults argResults;
    late Auth auth;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AuthTokenCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      auth = MockAuth();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      argResults = MockArgResults();
      when(() => argResults.rest).thenReturn([]);
      command = AuthTokenCommand()..testArgResults = argResults;

      when(() => logger.level).thenReturn(Level.info);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(() => auth.accessToken()).thenAnswer((_) async => 'sb_at_test');
      when(() => auth.credentialKind).thenReturn(CredentialKind.login);
      when(() => auth.accessTokenExpiresAt).thenReturn(expiresAt);
    });

    test('is named token, with a print-access-token alias', () {
      expect(command.name, equals('token'));
      expect(command.aliases, equals(['print-access-token']));
      expect(command.reservesStdout, isTrue);
      expect(command.description, contains('secret'));
    });

    group('with arguments', () {
      Future<Map<String, dynamic>> runWithRest(List<String> rest) async {
        when(() => argResults.rest).thenReturn(rest);
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.usage.code));
        verifyNever(() => auth.accessToken());
        expect(json, isNot(contains('data')));
        return json['error'] as Map<String, dynamic>;
      }

      test('points API key verbs at shorebird tokens', () async {
        final error = await runWithRest(['create']);
        expect(error['message'], contains('takes no arguments'));
        expect(
          error['hint'],
          'API keys (for SHOREBIRD_TOKEN in CI) are managed with '
          '`shorebird tokens create`.',
        );
      });

      test('points anything else at shorebird tokens', () async {
        final error = await runWithRest(['generate']);
        expect(
          error['hint'],
          'API keys (for SHOREBIRD_TOKEN in CI) are managed with '
          '`shorebird tokens`.',
        );
      });
    });

    test('returns the precondition exit code when not authenticated', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      final captured = <String>[];
      final result = await captureStdout(
        () => runWithOverrides(command.run),
        captured: captured,
      );
      expect(result, equals(exception.exitCode.code));
      expect(captured, isEmpty);
      verifyNever(() => auth.accessToken());
    });

    test('writes only the token to stdout', () async {
      final captured = <String>[];
      final result = await captureStdout(
        () => runWithOverrides(command.run),
        captured: captured,
      );
      expect(result, equals(ExitCode.success.code));
      expect(captured, equals(['sb_at_test']));
    });

    test("leaves the token out of the run's log file", () async {
      final logFile = File(
        p.join(Directory.systemTemp.createTempSync().path, 'run.log'),
      )..createSync();
      final captured = <String>[];
      final realStdout = stdout;
      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        stdout: () => LoggingStdout(
          baseStdOut: CapturingStdout(
            baseStdOut: realStdout,
            captured: captured,
          ),
          logFile: logFile,
        ),
      );
      expect(result, equals(ExitCode.success.code));
      expect(captured, equals(['sb_at_test']));
      expect(logFile.readAsStringSync(), isNot(contains('sb_at_test')));
    });

    test('emits the token as JSON', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'token': 'sb_at_test',
        'credential': 'login',
        'expires_at': '2026-10-17T01:00:00.000Z',
      });
    });

    test('emits a JSON error when no token can be had', () async {
      when(
        () => auth.accessToken(),
      ).thenThrow(ProcessExit(ExitCode.tempFail.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.tempFail.code));
      expect(json['error'], {
        'code': 'fetch_failed',
        'message': 'Failed to get an access token.',
      });
    });
  });
}
