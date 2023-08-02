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

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  group(BuildAppBundleCommand, () {
    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Doctor doctor;
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late BuildAppBundleCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      doctor = _MockDoctor();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdValidator = _MockShorebirdValidator();

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
        () => doctor.androidCommandValidators,
      ).thenReturn([flutterValidator]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(BuildAppBundleCommand.new)
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

    test('exits with code 70 when building appbundle fails', () async {
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
          ['build', 'appbundle', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building appbundle succeeds', () async {
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
          ['build', 'appbundle', '--release'],
          runInShell: true,
        ),
      ).called(1);

      verify(
        () => logger.info(
          '''
📦 Generated an app bundle at:
${lightCyan.wrap(p.join('build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab'))}''',
        ),
      ).called(1);
    });

    test(
        'exits with code 0 when building appbundle succeeds '
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
            'appbundle',
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
📦 Generated an app bundle at:
${lightCyan.wrap(p.join('build', 'app', 'outputs', 'bundle', '${flavor}Release', 'app-$flavor-release.aab'))}''',
        ),
      ).called(1);
    });

    test('local-engine and architectures', () async {
      expect(
        runWithOverrides(() => command.architectures.length),
        greaterThan(1),
      );

      expect(
        runScoped(
          () => command.architectures.length,
          values: {
            engineConfigRef.overrideWith(
              () => const EngineConfig(
                localEngine: 'android_release_arm64',
                localEngineSrcPath: 'path/to/engine/src',
              ),
            )
          },
        ),
        equals(1),
      );

      // We only support a few release configs for now.
      expect(
        () => runScoped(
          () => command.architectures.length,
          values: {
            engineConfigRef.overrideWith(
              () => const EngineConfig(
                localEngine: 'android_debug_unopt',
                localEngineSrcPath: 'path/to/engine/src',
              ),
            )
          },
        ),
        throwsException,
      );
    });
  });
}
