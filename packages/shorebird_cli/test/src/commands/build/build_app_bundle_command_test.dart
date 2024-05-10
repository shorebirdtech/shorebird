import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(BuildAppBundleCommand, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late Doctor doctor;
    late ShorebirdLogger logger;
    late BuildAppBundleCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(Directory(''));
    });

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      doctor = MockDoctor();
      logger = MockShorebirdLogger();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
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
      when(
        () => artifactBuilder.buildAppBundle(
          flavor: any(named: 'flavor'),
          target: any(named: 'target'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => File(''));

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
      when(
        () => artifactBuilder.buildAppBundle(
          args: any(named: 'args'),
        ),
      ).thenThrow(
        ArtifactBuildException('Failed to build: oops'),
      );

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => artifactBuilder.buildAppBundle(args: []),
      ).called(1);
    });

    group('when platform was specified via arg results rest', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['android', '--verbose']);
      });

      test('exits with code 0 when building appbundle succeeds', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => artifactBuilder.buildAppBundle(
            args: ['--verbose'],
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
    });

    test('exits with code 0 when building appbundle succeeds', () async {
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => artifactBuilder.buildAppBundle(
          args: [],
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
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => artifactBuilder.buildAppBundle(
          flavor: flavor,
          target: target,
          args: [],
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
        runWithOverrides(() => AndroidArch.availableAndroidArchs.length),
        greaterThan(1),
      );

      expect(
        runScoped(
          () => AndroidArch.availableAndroidArchs.length,
          values: {
            engineConfigRef.overrideWith(
              () => const EngineConfig(
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
          () => AndroidArch.availableAndroidArchs.length,
          values: {
            engineConfigRef.overrideWith(
              () => const EngineConfig(
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
  });
}
