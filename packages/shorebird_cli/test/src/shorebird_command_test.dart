import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

class _TestCommand extends ShorebirdCommand {
  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing ShorebirdCommand.';
}

void main() {
  useTempWorkingDirectory();
  group(ShorebirdCommand, () {
    final cryptoFixturesBasePath = p.join(fixturesDirectory, 'crypto');
    final publicKeyFile = File(p.join(cryptoFixturesBasePath, 'public.pem'));
    final privateKeyFile = File(p.join(cryptoFixturesBasePath, 'private.pem'));

    late ArgParser parser;
    late _TestCommand command;

    /// A [command] whose results come from parsing [args].
    _TestCommand commandWith(List<String> args) => command
      ..testArgResults = parser.parse(args)
      ..testRunner = usageRunner();

    Matcher throwsUsage(String message) => throwsA(
      isA<UsageException>().having((e) => e.message, 'message', message),
    );

    setUp(() {
      parser = ArgParser()
        ..addOption(CommonArguments.publicKeyArg.name)
        ..addOption(CommonArguments.privateKeyArg.name)
        ..addOption(CommonArguments.publicKeyCmd.name)
        ..addOption(CommonArguments.signCmd.name);
      command = _TestCommand();
    });

    group('assertSigningArgsValid', () {
      test('succeeds when no signing arguments provided', () {
        expect(commandWith([]).assertSigningArgsValid, returnsNormally);
      });

      test('throws when both public key sources provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--public-key-cmd=get-key-cmd',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          throwsUsage(
            'Pass either --public-key-path or --public-key-cmd, not both.',
          ),
        );
      });

      test('throws when both signing methods provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=${privateKeyFile.path}',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          throwsUsage(
            'Pass either --private-key-path or --sign-cmd, not both.',
          ),
        );
      });

      test('throws when sign-cmd provided without any public key', () {
        expect(
          commandWith(['--sign-cmd=sign-cmd']).assertSigningArgsValid,
          throwsUsage(
            '--sign-cmd requires a public key: add --public-key-path=<path> '
            'or --public-key-cmd=<command>.',
          ),
        );
      });

      test('throws naming the missing key when only one file is given', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--public-key-path and --private-key-path must be passed '
            'together (missing --private-key-path).',
          ),
        );
        expect(
          commandWith([
            '--private-key-path=${privateKeyFile.path}',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--public-key-path and --private-key-path must be passed '
            'together (missing --public-key-path).',
          ),
        );
      });

      test('throws naming the flag when a key file does not exist', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=/nope/private.pem',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--private-key-path: no file found at /nope/private.pem.',
          ),
        );
      });

      test('succeeds when both cmd arguments provided', () {
        expect(
          commandWith([
            '--public-key-cmd=get-key-cmd',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });

      test('succeeds with public-key-path + sign-cmd (mixed)', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });

      test('succeeds when both file arguments provided with valid files', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=${privateKeyFile.path}',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });
    });

    group('assertPublicKeyArgsValid', () {
      test('succeeds when no public key arguments provided', () {
        expect(commandWith([]).assertPublicKeyArgsValid, returnsNormally);
      });

      test('succeeds when only public-key-path provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
          ]).assertPublicKeyArgsValid,
          returnsNormally,
        );
      });

      test('succeeds when only public-key-cmd provided', () {
        expect(
          commandWith([
            '--public-key-cmd=get-key-cmd',
          ]).assertPublicKeyArgsValid,
          returnsNormally,
        );
      });

      test('throws when both public-key-path and public-key-cmd provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--public-key-cmd=get-key-cmd',
          ]).assertPublicKeyArgsValid,
          throwsUsage(
            'Pass either --public-key-path or --public-key-cmd, not both.',
          ),
        );
      });

      test('throws naming the flag when the public key does not exist', () {
        expect(
          commandWith([
            '--public-key-path=/nope/public.pem',
          ]).assertPublicKeyArgsValid,
          throwsUsage('--public-key-path: no file found at /nope/public.pem.'),
        );
      });
    });

    group('reportError', () {
      late ShorebirdLogger logger;

      R runWithOverrides<R>(R Function() body, {required bool jsonMode}) {
        return runScoped(
          body,
          values: {
            isJsonModeRef.overrideWith(() => jsonMode),
            loggerRef.overrideWith(() => logger),
          },
        );
      }

      setUp(() {
        logger = MockShorebirdLogger();
      });

      group('when not in JSON mode', () {
        test('logs the message and hint, returns a usage error', () {
          final exitCode = runWithOverrides(
            () => command.reportError(
              message: 'Something is wrong.',
              hint: 'Try again.',
            ),
            jsonMode: false,
          );

          expect(exitCode, equals(ExitCode.usage.code));
          verify(() => logger.err('Something is wrong.')).called(1);
          verify(() => logger.info('Try again.')).called(1);
        });

        test('logs no hint when none is given', () {
          runWithOverrides(
            () => command.reportError(message: 'Something is wrong'),
            jsonMode: false,
          );

          verify(() => logger.err('Something is wrong')).called(1);
          verifyNever(() => logger.info(any()));
        });

        test('returns the given exit code', () {
          final exitCode = runWithOverrides(
            () => command.reportError(
              message: 'Something is wrong',
              exitCode: ExitCode.software.code,
            ),
            jsonMode: false,
          );

          expect(exitCode, equals(ExitCode.software.code));
        });
      });

      group('when in JSON mode', () {
        test('emits an error envelope and logs nothing', () async {
          final result = await captureJson(
            () async => runWithOverrides(
              () => command.reportError(
                message: 'Something is wrong.',
                hint: 'Try again.',
                code: JsonErrorCode.fetchFailed,
              ),
              jsonMode: true,
            ),
          );

          expect(result.exitCode, equals(ExitCode.usage.code));
          expect(result.json['status'], equals('error'));
          expect(
            result.json['error'],
            equals({
              'code': 'fetch_failed',
              'message': 'Something is wrong.',
              'hint': 'Try again.',
            }),
          );
          verifyNever(() => logger.err(any()));
          verifyNever(() => logger.info(any()));
        });
      });
    });

    group('reportApiError', () {
      late ShorebirdLogger logger;

      R runWithOverrides<R>(R Function() body, {required bool jsonMode}) {
        return runScoped(
          body,
          values: {
            isJsonModeRef.overrideWith(() => jsonMode),
            loggerRef.overrideWith(() => logger),
          },
        );
      }

      final fullError = CodePushException(
        message: 'The account requires an upgraded plan.',
        details: 'Some details.',
        response: ErrorResponse(
          code: 'shorebird_plan_insufficient_tier',
          message: 'The account requires an upgraded plan.',
          documentationUrl: Uri.parse('https://docs.shorebird.dev/plans'),
        ),
      );

      setUp(() {
        logger = MockShorebirdLogger();
      });

      group('when not in JSON mode', () {
        test('logs the message, details and code', () {
          final exitCode = runWithOverrides(
            () => command.reportApiError(
              fullError,
              message: 'Failed to fetch things.',
            ),
            jsonMode: false,
          );

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              'Failed to fetch things. The account requires an upgraded plan.',
            ),
          ).called(1);
          verify(() => logger.info('Some details.')).called(1);
          verify(
            () => logger.info('Error code: shorebird_plan_insufficient_tier'),
          ).called(1);
        });

        test('logs only the message when there is no code or details', () {
          runWithOverrides(
            () => command.reportApiError(
              const CodePushException(message: 'Oops.'),
              message: 'Failed to fetch things.',
            ),
            jsonMode: false,
          );

          verify(() => logger.err('Failed to fetch things. Oops.')).called(1);
          verifyNever(() => logger.info(any()));
        });
      });

      group('when in JSON mode', () {
        test('emits the API code, details and documentation in the '
            'envelope', () async {
          final result = await captureJson(
            () async => runWithOverrides(
              () => command.reportApiError(
                fullError,
                message: 'Failed to fetch things.',
              ),
              jsonMode: true,
            ),
          );

          expect(result.exitCode, equals(ExitCode.software.code));
          expect(
            result.json['error'],
            equals({
              'code': 'fetch_failed',
              'message':
                  'Failed to fetch things. '
                  'The account requires an upgraded plan.',
              'api_code': 'shorebird_plan_insufficient_tier',
              'details': 'Some details.',
              'documentation_url': 'https://docs.shorebird.dev/plans',
            }),
          );
          verifyNever(() => logger.err(any()));
        });
      });
    });

    group('reportPreconditionFailure', () {
      late ShorebirdLogger logger;

      R runWithOverrides<R>(R Function() body, {required bool jsonMode}) {
        return runScoped(
          body,
          values: {
            isJsonModeRef.overrideWith(() => jsonMode),
            loggerRef.overrideWith(() => logger),
          },
        );
      }

      setUp(() {
        logger = MockShorebirdLogger();
      });

      test('in human mode, prints nothing more and returns the exit code', () {
        final exitCode = runWithOverrides(
          () => command.reportPreconditionFailure(UserNotAuthorizedException()),
          jsonMode: false,
        );

        expect(exitCode, equals(ExitCode.noUser.code));
        verifyZeroInteractions(logger);
      });

      test('in human mode, writes nothing to stdout', () async {
        final captured = <String>[];
        await captureStdout(
          () async => runWithOverrides(
            () => command.reportPreconditionFailure(
              ShorebirdNotInitializedException(),
            ),
            jsonMode: false,
          ),
          captured: captured,
        );
        expect(captured, isEmpty);
      });

      final failures = <String, PreconditionFailedException>{
        'logged out': UserNotAuthorizedException(),
        'not initialized': ShorebirdNotInitializedException(),
        'validators failed': ValidationFailedException(
          message: 'Aborting due to validation errors. Missing thing.',
          hint: '1 issue can be fixed automatically.',
        ),
        'unsupported OS': UnsupportedOperatingSystemException(
          message: 'This command is only supported on macos.',
        ),
      };
      for (final MapEntry(key: name, value: failure) in failures.entries) {
        test('in JSON mode, emits precondition_failed for $name', () async {
          final result = await captureJson(
            () async => runWithOverrides(
              () => command.reportPreconditionFailure(failure),
              jsonMode: true,
            ),
          );

          expect(result.exitCode, equals(failure.exitCode.code));
          expect(result.json['status'], equals('error'));
          expect(
            result.json['error'],
            equals({
              'code': 'precondition_failed',
              'message': failure.message,
              if (failure.hint != null) 'hint': failure.hint,
            }),
          );
          verifyNever(() => logger.err(any()));
        });
      }
    });

    group('guardApiCall', () {
      late ShorebirdLogger logger;

      R runWithOverrides<R>(R Function() body, {required bool jsonMode}) {
        return runScoped(
          body,
          values: {
            isJsonModeRef.overrideWith(() => jsonMode),
            loggerRef.overrideWith(() => logger),
          },
        );
      }

      Future<int?> guard(Future<void> Function() body) => command.guardApiCall(
        body,
        code: JsonErrorCode.fetchFailed,
        message: 'Failed to fetch things.',
      );

      setUp(() {
        logger = MockShorebirdLogger();
      });

      group('when the call succeeds', () {
        for (final jsonMode in [false, true]) {
          test('runs the call and returns null (json: $jsonMode)', () async {
            var called = false;
            final captured = <String>[];
            final errorCode = await captureStdout(
              () => runWithOverrides(
                () => guard(() async => called = true),
                jsonMode: jsonMode,
              ),
              captured: captured,
            );

            expect(called, isTrue);
            expect(errorCode, isNull);
            expect(captured, isEmpty);
          });
        }
      });

      group('when not in JSON mode', () {
        test('rethrows a ProcessExit and emits nothing', () async {
          final captured = <String>[];
          await expectLater(
            captureStdout(
              () => runWithOverrides(
                () => guard(() async => throw ProcessExit(70)),
                jsonMode: false,
              ),
              captured: captured,
            ),
            throwsA(
              isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', 70),
            ),
          );
          expect(captured, isEmpty);
          verifyNever(() => logger.err(any()));
        });
      });

      group('when in JSON mode', () {
        test('emits one error envelope and returns the exit code', () async {
          final result = await captureJson(
            () async => (await runWithOverrides<Future<int?>>(
              () => guard(() async => throw ProcessExit(70)),
              jsonMode: true,
            ))!,
          );

          expect(result.exitCode, equals(70));
          expect(result.json['status'], equals('error'));
          expect(
            result.json['error'],
            equals({
              'code': 'fetch_failed',
              'message': 'Failed to fetch things.',
            }),
          );
          verifyNever(() => logger.err(any()));
        });

        test('reports a failed API call with its code and details', () async {
          final result = await captureJson(
            () async => (await runWithOverrides<Future<int?>>(
              () => guard(
                () async => throw ApiErrorExit(
                  const CodePushException(
                    message: 'Plan lacks this feature.',
                    response: ErrorResponse(
                      code: 'shorebird_plan_insufficient_tier',
                      message: 'Plan lacks this feature.',
                    ),
                    details: 'Upgrade to Business.',
                  ),
                  70,
                ),
              ),
              jsonMode: true,
            ))!,
          );

          expect(result.exitCode, equals(70));
          expect(
            result.json['error'],
            equals({
              'code': 'fetch_failed',
              'message': 'Failed to fetch things. Plan lacks this feature.',
              'api_code': 'shorebird_plan_insufficient_tier',
              'details': 'Upgrade to Business.',
            }),
          );
        });

        test('lets other exceptions through', () async {
          final captured = <String>[];
          await expectLater(
            captureStdout(
              () => runWithOverrides(
                () => guard(() async => throw Exception('oops')),
                jsonMode: true,
              ),
              captured: captured,
            ),
            throwsA(isA<Exception>()),
          );
          expect(captured, isEmpty);
        });

        test('rethrows a failed precondition rather than reporting it as '
            'its own error', () async {
          final failure = PreconditionFailedExit(UserNotAuthorizedException());
          final captured = <String>[];
          await expectLater(
            captureStdout(
              () => runWithOverrides(
                () => guard(() async => throw failure),
                jsonMode: true,
              ),
              captured: captured,
            ),
            throwsA(same(failure)),
          );
          expect(captured, isEmpty);
        });
      });
    });
  });
}
