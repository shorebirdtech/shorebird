import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockDoctor extends Mock implements Doctor {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(BuildApkCommand, () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Doctor doctor;
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late BuildApkCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      doctor = _MockDoctor();
      logger = _MockLogger();
      shorebirdProcess = _MockShorebirdProcess();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdValidator = _MockShorebirdValidator();

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
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => doctor.androidCommandValidators,
      ).thenReturn([flutterValidator]);

      command = runWithOverrides(BuildApkCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
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
          checkShorebirdInitialized: true,
          validators: [flutterValidator],
        ),
      ).called(1);
    });

    test('exits with code 70 when building apk fails', () async {
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
          ['build', 'apk', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building apk succeeds', () async {
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
          ['build', 'apk', '--release'],
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an apk at:
${lightCyan.wrap(p.join('build', 'app', 'outputs', 'apk', 'release', 'app-release.apk'))}''',
        ),
      ).called(1);
    });

    test(
        'exits with code 0 when building apk succeeds '
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
            'apk',
            '--release',
            '--flavor=$flavor',
            '--target=$target',
          ],
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an apk at:
${lightCyan.wrap(p.join('build', 'app', 'outputs', 'apk', flavor, 'release', 'app-$flavor-release.apk'))}''',
        ),
      ).called(1);
    });
  });
}
