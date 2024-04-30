import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(BuildAarCommand, () {
    const buildNumber = '1.0';
    const androidPackageName = 'com.example.my_flutter_module';

    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late Logger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late BuildAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      logger = MockLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => artifactBuilder.buildAar(buildNumber: any(named: 'buildNumber')),
      ).thenAnswer((_) async => {});
      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

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
      when(
        () => artifactBuilder.buildAar(buildNumber: any(named: 'buildNumber')),
      ).thenThrow(const ProcessException('git', ['reset'], 'error'));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => artifactBuilder.buildAar(buildNumber: buildNumber))
          .called(1);
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 0 when building aar succeeds', () async {
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      verify(() => artifactBuilder.buildAar(buildNumber: buildNumber))
          .called(1);
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
  });
}
