import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
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

void main() {
  group('build apk', () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late ProcessResult processResult;
    late BuildApkCommand command;
    late ShorebirdFlutterValidator flutterValidator;

    String? processExecutable;
    List<String>? processArguments;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      processExecutable = null;
      processArguments = null;
      command = BuildApkCommand(
        auth: auth,
        logger: logger,
        runProcess: (
          executable,
          arguments, {
          bool runInShell = false,
          Map<String, String>? environment,
          String? workingDirectory,
          bool useVendedFlutter = true,
        }) async {
          processExecutable = executable;
          processArguments = arguments;
          return processResult;
        },
        validators: [flutterValidator],
      )..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => flutterValidator.validate()).thenAnswer((_) async => []);
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

    test('exits with code 70 when building apk fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();

      final result = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
      expect(processExecutable, equals('flutter'));
      expect(processArguments, equals(['build', 'apk', '--release']));
    });

    test('exits with code 0 when building apk succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));
      expect(processExecutable, equals('flutter'));
      expect(processArguments, equals(['build', 'apk', '--release']));
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
