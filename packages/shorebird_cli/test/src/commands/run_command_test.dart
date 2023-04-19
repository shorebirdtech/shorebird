import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements Process {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockAndroidInternetPermissionValidator extends Mock
    implements AndroidInternetPermissionValidator {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('run', () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late Process process;
    late CodePushClient codePushClient;
    late RunCommand runCommand;
    late AndroidInternetPermissionValidator androidInternetPermissionValidator;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      process = _MockProcess();
      shorebirdProcess = _MockShorebirdProcess();
      codePushClient = _MockCodePushClient();
      androidInternetPermissionValidator =
          _MockAndroidInternetPermissionValidator();
      flutterValidator = _MockShorebirdFlutterValidator();
      runCommand = RunCommand(
        auth: auth,
        logger: logger,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        validators: [
          androidInternetPermissionValidator,
          flutterValidator,
        ],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();

      registerFallbackValue(shorebirdProcess);

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
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer((_) async => []);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runCommand.run();
      expect(result, equals(ExitCode.noUser.code));

      verify(() => logger.err('You must be logged in to run.')).called(1);
      verify(
        () => logger.err("Run 'shorebird login' to log in and try again."),
      ).called(1);
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
      when(() => process.stderr).thenAnswer(
        (_) => Stream.value(utf8.encode(error)),
      );
      when(() => process.exitCode).thenAnswer((_) async => exitCode);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
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
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(
        () => process.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(ExitCode.success.code));
      verify(() => logger.info(output)).called(1);
    });

    test('prints validation warnings', () async {
      when(() => flutterValidator.validate(any())).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'Flutter issue',
          ),
        ],
      );
      when(() => androidInternetPermissionValidator.validate(any())).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'Android issue',
          ),
        ],
      );
      final tempDir = Directory.systemTemp.createTempSync();

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const output = 'some output';
      when(
        () => process.stdout,
      ).thenAnswer((_) => Stream.value(utf8.encode(output)));
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(
        () => process.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(ExitCode.success.code));
      verify(() => logger.info(output)).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Android issue'))),
      ).called(1);
    });
  });
}
