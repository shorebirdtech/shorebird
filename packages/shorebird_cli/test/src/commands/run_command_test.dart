import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(RunCommand, () {
    late ArgResults argResults;
    late Doctor doctor;
    late Logger logger;
    late Process process;
    late ShorebirdProcess shorebirdProcess;
    late IOSink ioSink;
    late ShorebirdValidator shorebirdValidator;
    late Validator validator;
    late RunCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
    });

    setUp(() {
      argResults = MockArgResults();
      doctor = MockDoctor();
      logger = MockLogger();
      process = MockProcess();
      shorebirdProcess = MockShorebirdProcess();
      ioSink = MockIOSink();
      shorebirdValidator = MockShorebirdValidator();
      validator = MockValidator();

      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => process);
      when(() => argResults.rest).thenReturn([]);
      when(() => doctor.allValidators).thenReturn([validator]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => ioSink.addStream(any())).thenAnswer((_) async {});
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(RunCommand.new)..testArgResults = argResults;
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

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          validators: any(named: 'validators'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          validators: [validator],
        ),
      ).called(1);
    });

    test('exits with code when running the app fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final progress = MockProgress();
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

      final progress = MockProgress();
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

      final progress = MockProgress();
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
