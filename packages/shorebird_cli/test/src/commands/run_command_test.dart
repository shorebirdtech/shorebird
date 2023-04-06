import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
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

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

void main() {
  group('run', () {
    late ArgResults argResults;
    late Directory applicationConfigHome;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late Process process;
    late CodePushClient codePushClient;
    late RunCommand runCommand;
    late ShorebirdFlutterValidator flutterValidator;

    setUp(() {
      argResults = _MockArgResults();
      applicationConfigHome = Directory.systemTemp.createTempSync();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      process = _MockProcess();
      codePushClient = _MockCodePushClient();
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
        startProcess: (executable, arguments, {bool runInShell = false}) async {
          return process;
        },
        flutterValidator: flutterValidator,
      )..testArgResults = argResults;

      testApplicationConfigHome = (_) => applicationConfigHome.path;

      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => flutterValidator.validate()).thenAnswer((_) async => []);
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

    test('exits with code 70 when downloading engine fails', () async {
      final error = Exception('oops');
      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenThrow(error);
      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await runCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(progress.fail).called(1);
      verify(
        () => logger.err(
          'Exception: Failed to download shorebird engine: $error',
        ),
      ).called(1);
    });

    test('exits with code 70 when building the engine fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenAnswer((_) async => Uint8List(0));
      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );
      expect(result, equals(ExitCode.software.code));

      verify(progress.fail).called(1);
      verify(
        () => logger.err(
          any(that: contains('Failed to build shorebird engine:')),
        ),
      ).called(1);
    });

    test('exits with code when running the app fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      ZipFileEncoder()
        ..create(p.join(runCommand.shorebirdEnginePath, 'engine.zip'))
        ..close();

      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenAnswer((_) async => Uint8List(0));

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
      Directory(
        p.join(runCommand.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);

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

    test('prints flutter validation warnings', () async {
      when(() => flutterValidator.validate()).thenAnswer(
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
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(
        p.join(runCommand.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);

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
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });
  });
}
