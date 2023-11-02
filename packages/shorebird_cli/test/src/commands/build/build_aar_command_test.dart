import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(BuildAarCommand, () {
    const buildNumber = '1.0';
    const androidPackageName = 'com.example.my_flutter_module';

    late ArgResults argResults;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult buildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdValidator shorebirdValidator;
    late BuildAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      logger = MockLogger();
      flutterPubGetProcessResult = MockProcessResult();
      buildProcessResult = MockProcessResult();
      operatingSystemInterface = MockOperatingSystemInterface();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(progress);

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
      ).thenAnswer((invocation) async {
        return buildProcessResult;
      });

      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);

      command = runWithOverrides(BuildAarCommand.new)
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
        ),
      ).called(1);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      when(() => shorebirdEnv.androidPackageName).thenReturn(null);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.config.code);
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => buildProcessResult.exitCode).thenReturn(1);
      when(() => buildProcessResult.stderr).thenReturn('oops');

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 0 when building aar succeeds', () async {
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an aar at:
${lightCyan.wrap(
            p.join(
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'my_flutter_module',
              'flutter_release',
              buildNumber,
              'flutter_release-$buildNumber.aar',
            ),
          )}''',
        ),
      ).called(1);
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
