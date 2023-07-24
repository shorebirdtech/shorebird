import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockDoctor extends Mock implements Doctor {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements Process {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockIOSink extends Mock implements IOSink {}

class _MockValidator extends Mock implements Validator {}

void main() {
  group(RunCommand, () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Doctor doctor;
    late Logger logger;
    late Process process;
    late CodePushClient codePushClient;
    late ShorebirdProcess shorebirdProcess;
    late RunCommand command;
    late IOSink ioSink;
    late Validator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
    });

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      doctor = _MockDoctor();
      logger = _MockLogger();
      process = _MockProcess();
      shorebirdProcess = _MockShorebirdProcess();
      codePushClient = _MockCodePushClient();
      ioSink = _MockIOSink();
      validator = _MockValidator();

      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => process);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => doctor.allValidators).thenReturn([validator]);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => ioSink.addStream(any())).thenAnswer((_) async {});
      when(() => validator.validate()).thenAnswer((_) async => []);

      command = runWithOverrides(
        () => RunCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('command is hidden', () {
      expect(command.hidden, isTrue);
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('logs deprecation warning', () async {
      runWithOverrides(command.run).ignore();

      verify(
        () => logger.warn('''
This command is deprecated and will be removed in a future release.
Please use "shorebird preview" instead.'''),
      ).called(1);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.noUser.code));

      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
    });

    test('aborts on validation errors', () async {
      when(() => validator.validate()).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'Android issue',
          ),
        ],
      );

      final result = await runWithOverrides(command.run);

      await expectLater(result, equals(ExitCode.config.code));
      verify(
        () => logger.info(any(that: contains('Android issue'))),
      ).called(1);
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
      verifyNever(() => logger.info('Running app...'));
    });

    test('exits with code when running the app fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const error = 'oops something went wrong';
      const exitCode = 1;
      when(
        () => process.stdout,
      ).thenAnswer((_) => const Stream.empty());
      when(() => process.stdin).thenAnswer((_) => ioSink);
      when(() => process.stderr).thenAnswer(
        (_) => Stream.value(utf8.encode(error)),
      );
      when(() => process.exitCode).thenAnswer((_) async => exitCode);

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(exitCode));
      verify(() => logger.err(error)).called(1);
    });

    test('exits with code 0 when running the app succeeds', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const output = 'some output';
      when(
        () => process.stdout,
      ).thenAnswer((_) => Stream.value(utf8.encode(output)));
      when(() => process.stdin).thenAnswer((_) => ioSink);
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(
        () => process.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(ExitCode.success.code));
      verify(() => logger.info(output)).called(1);
      verify(() => ioSink.addStream(any())).called(1);
    });

    test('passes additional args when specified', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const deviceId = 'test-device-id';
      const flavor = 'development';
      const target = './lib/main_development.dart';
      const dartDefines = ['FOO=BAR', 'BAZ=QUX'];
      when(() => argResults['device-id']).thenReturn(deviceId);
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      when(() => argResults['dart-define']).thenReturn(dartDefines);

      when(() => process.stdout).thenAnswer((_) => const Stream.empty());
      when(() => process.stdin).thenAnswer((_) => ioSink);
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(
        () => process.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      final args = verify(
        () => shorebirdProcess.start(
          any(),
          captureAny(),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured.first as List<String>;
      expect(
        args,
        equals([
          'run',
          '--release',
          '--device-id=$deviceId',
          '--flavor=$flavor',
          '--target=$target',
          '--dart-define=${dartDefines[0]}',
          '--dart-define=${dartDefines[1]}',
        ]),
      );

      await expectLater(result, equals(ExitCode.success.code));
    });
  });
}
