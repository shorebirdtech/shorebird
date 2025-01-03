import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(WindowsReleaser, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late CodePushClientWrapper codePushClientWrapper;
    late Doctor doctor;
    late ShorebirdLogger logger;
    late FlavorValidator flavorValidator;
    late Directory projectRoot;
    late Powershell powershell;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late WindowsReleaser releaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          powershellRef.overrideWith(() => powershell),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.windows);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      flavorValidator = MockFlavorValidator();
      powershell = MockPowershell();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      releaser = WindowsReleaser(
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('releaseType', () {
      test('is windows', () {
        expect(releaser.releaseType, ReleaseType.windows);
      });
    });

    group('assertArgsAreValid', () {
      // TODO
    });

    group('assertPreconditions', () {
      setUp(() {
        when(() => doctor.windowsCommandValidators)
            .thenReturn([flavorValidator]);
        when(flavorValidator.validate).thenAnswer((_) async => []);
      });

      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
              supportedOperatingSystems:
                  any(named: 'supportedOperatingSystems'),
            ),
          ).thenAnswer((_) async {});
        });

        test('returns normally', () async {
          await expectLater(
            () => runWithOverrides(releaser.assertPreconditions),
            returnsNormally,
          );
        });
      });

      group('when validation fails', () {
        final exception = ValidationFailedException();

        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
              supportedOperatingSystems:
                  any(named: 'supportedOperatingSystems'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(releaser.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [flavorValidator],
              supportedOperatingSystems: {Platform.windows},
            ),
          ).called(1);
        });
      });
    });

    group('buildReleaseArtifacts', () {
      setUp(() {
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => '3.27.1');
      });

      group('when builder throws exception', () {
        setUp(() {
          when(
            () => artifactBuilder.buildWindowsApp(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              args: any(named: 'args'),
              buildProgress: any(named: 'buildProgress'),
            ),
          ).thenThrow(Exception('oh no'));
        });

        test('fails progress, exits', () async {
          await expectLater(
            () => runWithOverrides(releaser.buildReleaseArtifacts),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail('Exception: oh no')).called(1);
        });
      });

      group('when build succeeds', () {
        setUp(() {
          when(
            () => artifactBuilder.buildWindowsApp(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              args: any(named: 'args'),
              buildProgress: any(named: 'buildProgress'),
            ),
          ).thenAnswer((_) async => projectRoot);
        });

        test('returns path to release directory', () async {
          final releaseDir =
              await runWithOverrides(releaser.buildReleaseArtifacts);
          expect(releaseDir, projectRoot);
        });
      });
    });

    group('getReleaseVersion', () {
      group('when exe does not exist', () {
        test('throws exception', () {
          expect(
            () => runWithOverrides(
              () => releaser.getReleaseVersion(
                releaseArtifactRoot: projectRoot,
              ),
            ),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('when exe exists', () {
        setUp(() {
          File(p.join(projectRoot.path, 'app.exe')).createSync();
          when(() => powershell.getExeVersionString(any())).thenAnswer(
            (_) async => '1.2.3',
          );
        });

        test('returns result of getExeVersionString', () async {
          await expectLater(
            runWithOverrides(
              () => releaser.getReleaseVersion(
                releaseArtifactRoot: projectRoot,
              ),
            ),
            completion(equals('1.2.3')),
          );
        });
      });
    });

    group('uploadReleaseArtifacts', () {
      const appId = 'my-app';
      const releaseId = 123;
      late Release release;

      setUp(() {
        release = MockRelease();
        when(() => release.id).thenReturn(releaseId);
      });

      group('when release directory does not exist', () {
        test('fails progress, exits', () async {
          await expectLater(
            () => runWithOverrides(
              () => releaser.uploadReleaseArtifacts(
                release: MockRelease(),
                appId: 'appId',
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err(
              any(that: startsWith('No release directory found at')),
            ),
          ).called(1);
        });
      });

      group('when release directory exists', () {
        setUp(() {
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'windows',
              'x64',
              'runner',
              'Release',
            ),
          ).createSync(recursive: true);

          when(
            () => codePushClientWrapper.createWindowsReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              projectRoot: any(named: 'projectRoot'),
              releaseZipPath: any(named: 'releaseZipPath'),
            ),
          ).thenAnswer((_) async {});
        });

        test('zips and uploads release directory', () async {
          await runWithOverrides(
            () => releaser.uploadReleaseArtifacts(
              release: release,
              appId: appId,
            ),
          );
          verify(
            () => codePushClientWrapper.createWindowsReleaseArtifacts(
              appId: appId,
              releaseId: releaseId,
              projectRoot: projectRoot.path,
              releaseZipPath: any(named: 'releaseZipPath'),
            ),
          ).called(1);
        });
      });
    });

    group('postReleaseInstructions', () {
      test('returns nonempty instructions', () {
        final instructions = releaser.postReleaseInstructions;
        expect(instructions, isNotEmpty);
      });
    });
  });
}
