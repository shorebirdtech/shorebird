import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/whoami_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(WhoamiCommand, () {
    const user = PrivateUser(
      id: 1,
      email: 'user@example.com',
      displayName: 'Example User',
      hasActiveSubscription: true,
      jwtIssuer: 'https://accounts.google.com',
      patchOverageLimit: 10000,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late Progress progress;
    late WhoamiCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(WhoamiCommand.new)
        ..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getCurrentUser(),
      ).thenAnswer((_) async => user);
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('Show the currently authenticated Shorebird user.'),
      );
    });

    group('when validation fails', () {
      final exception = UserNotAuthorizedException();

      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          ),
        ).thenThrow(exception);
      });

      test('returns the precondition failure exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    test('requires user to be authenticated', () async {
      await runWithOverrides(command.run);
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    group('human-readable output', () {
      test('prints account fields', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(any(that: contains('user@example.com'))),
        ).called(1);
        verify(
          () => logger.info(any(that: contains('Example User'))),
        ).called(1);
        verify(
          () => logger.info(any(that: contains('Plan:           paid'))),
        ).called(1);
        verify(
          () => logger.info(any(that: contains('Overage limit:  10000'))),
        ).called(1);
      });

      group('when display name is null', () {
        const userNoName = PrivateUser(
          id: 2,
          email: 'noname@example.com',
          jwtIssuer: 'https://accounts.google.com',
        );

        setUp(() {
          when(
            () => codePushClientWrapper.getCurrentUser(),
          ).thenAnswer((_) async => userNoName);
        });

        test('omits the display name line', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNever(
            () => logger.info(any(that: contains('Display name'))),
          );
        });
      });

      group('when user is on the free plan', () {
        const userNoSub = PrivateUser(
          id: 3,
          email: 'noplan@example.com',
          jwtIssuer: 'https://accounts.google.com',
        );

        setUp(() {
          when(
            () => codePushClientWrapper.getCurrentUser(),
          ).thenAnswer((_) async => userNoSub);
        });

        test('prints plan as free', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.info(any(that: contains('Plan:           free'))),
          ).called(1);
        });

        test('prints overage limit as none when unset', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.info(any(that: contains('Overage limit:  none'))),
          ).called(1);
        });
      });
    });

    group('when API fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getCurrentUser(),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in human-readable mode, rethrows ProcessExit', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('in --json mode, emits JSON error envelope', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'error');
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test('emits JSON success with projected user fields', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'success');
        final data = decoded['data'] as Map<String, dynamic>;
        final userData = data['user'] as Map<String, dynamic>;
        expect(userData['id'], 1);
        expect(userData['email'], 'user@example.com');
        expect(userData['display_name'], 'Example User');
        expect(userData['plan'], 'paid');
        expect(userData['overage_limit'], 10000);
      });

      test('does not leak protocol-internal fields', () async {
        final captured = <String>[];
        await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final userData =
            (decoded['data'] as Map<String, dynamic>)['user']
                as Map<String, dynamic>;
        expect(userData.containsKey('stripe_customer_id'), isFalse);
        expect(userData.containsKey('jwt_issuer'), isFalse);
        expect(userData.containsKey('has_active_subscription'), isFalse);
      });
    });
  });
}
