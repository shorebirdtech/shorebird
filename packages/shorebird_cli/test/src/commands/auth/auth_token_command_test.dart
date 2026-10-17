import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/auth/auth.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AuthTokenCommand, () {
    final expiresAt = DateTime.utc(2026, 10, 17, 1);

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
      command = AuthTokenCommand();

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

    test('returns the precondition exit code when not authenticated', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      final result = await runWithOverrides(command.run);
      expect(result, equals(exception.exitCode.code));
      verifyNever(() => auth.accessToken());
    });

    test('prints only the token', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('sb_at_test')).called(1);
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
