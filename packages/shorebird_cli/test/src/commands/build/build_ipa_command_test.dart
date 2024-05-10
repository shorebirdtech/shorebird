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
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(BuildIpaCommand, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late Doctor doctor;
    late Ios ios;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late BuildIpaCommand command;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          doctorRef.overrideWith(() => doctor),
          iosRef.overrideWith(() => ios),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      artifactBuilder = MockArtifactBuilder();
      argResults = MockArgResults();
      doctor = MockDoctor();
      ios = MockIos();
      logger = MockShorebirdLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults.rest).thenReturn([]);
      when(
        () => artifactBuilder.buildIpa(
          flavor: any(named: 'flavor'),
          target: any(named: 'target'),
          codesign: any(named: 'codesign'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => File(''));
      when(() => ios.createExportOptionsPlist()).thenReturn(File('.'));
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(() => shorebirdEnv.flutterRevision).thenReturn('1234');
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(BuildIpaCommand.new)
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

    test('exits with code 70 when building ipa fails', () async {
      when(
        () => artifactBuilder.buildIpa(
          flavor: any(named: 'flavor'),
          target: any(named: 'target'),
          codesign: any(named: 'codesign'),
          args: any(named: 'args'),
        ),
      ).thenThrow(ArtifactBuildException('oops'));

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => artifactBuilder.buildIpa(
          args: [],
        ),
      ).called(1);
    });

    group('when platform was specified via arg results rest', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['ios', '--verbose']);
      });

      test('exits with code 0 when building ipa succeeds', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.success.code));

        verify(
          () => artifactBuilder.buildIpa(args: ['--verbose']),
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
    });

    test('exits with code 0 when building ipa succeeds', () async {
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));

      verify(() => artifactBuilder.buildIpa(args: [])).called(1);

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
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => artifactBuilder.buildIpa(
          flavor: flavor,
          target: target,
          args: [],
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
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => artifactBuilder.buildIpa(codesign: false, args: []),
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
  });
}
