import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('build appbundle', () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late ProcessResult processResult;
    late BuildAppBundleCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      command = BuildAppBundleCommand(
        auth: auth,
        logger: logger,
        validators: [flutterValidator],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();

      registerFallbackValue(shorebirdProcess);

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => processResult);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
    });

    test('has correct description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await command.run();
      expect(result, equals(ExitCode.noUser.code));

      verify(() => logger.err('You must be logged in to build.')).called(1);
      verify(
        () => logger.err("Run 'shorebird login' to log in and try again."),
      ).called(1);
    });

    test('exits with code 70 when building appbundle fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();

      final result = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'appbundle', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building appbundle succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'appbundle', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('local-engine and architectures', () async {
      expect(command.architectures.length, greaterThan(1));

      command.testEngineConfig = const EngineConfig(
        localEngine: 'android_release_arm64',
        localEngineSrcPath: 'path/to/engine/src',
      );
      expect(command.architectures.length, equals(1));

      // We only support a few release configs for now.
      command.testEngineConfig = const EngineConfig(
        localEngine: 'android_debug_unopt',
        localEngineSrcPath: 'path/to/engine/src',
      );
      expect(() => command.architectures, throwsException);
    });

    test('prints flutter validation warnings', () async {
      when(() => flutterValidator.validate(any())).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'Flutter issue 1',
          ),
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'Flutter issue 2',
          ),
        ],
      );
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });
  });
}
