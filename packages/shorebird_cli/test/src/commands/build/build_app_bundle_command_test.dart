import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(BuildAppBundleCommand, () {
    late ArgResults argResults;
    late Doctor doctor;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdProcessResult buildProcessResult;
    late BuildAppBundleCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      doctor = MockDoctor();
      logger = MockLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      buildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdValidator = MockShorebirdValidator();

      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => buildProcessResult);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
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
      when(() => buildProcessResult.exitCode).thenReturn(1);
      when(() => buildProcessResult.stderr).thenReturn('oops');

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['build', 'appbundle', '--release'],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building appbundle succeeds', () async {
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
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
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
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
              () => EngineConfig(
                localEngine: 'android_release_arm64',
                localEngineSrcPath: 'path/to/engine/src',
                localEngineHost: 'host_release',
              ),
            ),
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
              () => EngineConfig(
                localEngine: 'android_debug_unopt',
                localEngineSrcPath: 'path/to/engine/src',
                localEngineHost: 'host_debug_unopt',
              ),
            ),
          },
        ),
        throwsException,
      );
    });

    test('runs flutter pub get with system flutter after successful build',
        () async {
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);

      await runWithOverrides(command.run);

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).called(1);
    });
  });
}
