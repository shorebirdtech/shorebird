import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(BuildIpaCommand, () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late BuildIpaCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      shorebirdProcess = _MockShorebirdProcess();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();

      registerFallbackValue(shorebirdProcess);

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => processResult);
      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);

      command = BuildIpaCommand(
        auth: auth,
        validators: [flutterValidator],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();
    });

    test('has correct description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.noUser.code));

      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
    });

    test('exits with code 70 when building ipa fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();

      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'ipa', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building ipa succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'ipa', '--release'],
          runInShell: true,
        ),
      ).called(1);

      verifyInOrder([
        () => logger.info(
              '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
            ),
        () => logger.info(
              '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
            ),
      ]);
    });

    test(
        'exits with code 0 when building ipa succeeds '
        'with flavor and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'ipa',
            '--release',
            '--flavor=$flavor',
            '--target=$target',
          ],
          runInShell: true,
        ),
      ).called(1);

      verifyInOrder([
        () => logger.info(
              '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
            ),
        () => logger.info(
              '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
            ),
      ]);
    });

    test(
        'exits with code 0 when building ipa succeeds '
        'with --no-codesign', () async {
      when(() => argResults['codesign']).thenReturn(false);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'ipa', '--release', '--no-codesign'],
          runInShell: true,
        ),
      ).called(1);

      verify(
        () => logger.info(
          '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
        ),
      ).called(1);

      verifyNever(
        () => logger.info(
          '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
        ),
      );
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

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });

    test('aborts if validation errors are present', () async {
      when(() => flutterValidator.validate(any())).thenAnswer(
        (_) async => [
          ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'There was an issue',
            fix: () async {},
          ),
        ],
      );

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              'issue can be fixed automatically',
              'shorebird doctor --fix',
            ]),
          ),
        ),
      ).called(1);
    });
  });
}
