import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(BuildApkCommand, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late Doctor doctor;
    late Logger logger;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdValidator shorebirdValidator;
    late BuildApkCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      doctor = MockDoctor();
      logger = MockLogger();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
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

      when(
        () => artifactBuilder.buildApk(
          flavor: any(named: 'flavor'),
          target: any(named: 'target'),
        ),
      ).thenAnswer((_) async => File(''));

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
      when(
        () => artifactBuilder.buildApk(
          flavor: any(named: 'flavor'),
          target: any(named: 'target'),
        ),
      ).thenThrow(BuildException('oops'));

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(() => artifactBuilder.buildApk()).called(1);
    });

    test('exits with code 0 when building apk succeeds', () async {
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));

      verify(() => artifactBuilder.buildApk()).called(1);
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
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => artifactBuilder.buildApk(
          flavor: flavor,
          target: target,
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
