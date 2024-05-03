import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/android_releaser.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AndroidReleaser, () {
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late Doctor doctor;
    late Platform platform;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdProcessResult flutterAppbundleBuildProcessResult;
    late ShorebirdProcessResult flutterApkBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late AndroidReleaser androidReleaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          shorebirdAndroidArtifactsRef
              .overrideWith(() => shorebirdAndroidArtifacts),
        },
      );
    }

    setUpAll(setExitFunctionForTests);

    tearDownAll(restoreExitFunction);

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      operatingSystemInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      progress = MockProgress();
      logger = MockLogger();
      flutterAppbundleBuildProcessResult = MockProcessResult();
      flutterApkBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = ShorebirdAndroidArtifacts();

      when(() => doctor.androidCommandValidators)
          .thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);

      androidReleaser = AndroidReleaser(
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('releaseType', () {
      test('is android', () {
        expect(androidReleaser.releaseType, ReleaseType.android);
      });
    });

    group('validatePreconditions', () {
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
            () => runWithOverrides(androidReleaser.validatePreconditions),
            returnsNormally,
          );
        });
      });

      group('when validation fails', () {
        setUp(() {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
          await expectLater(
            () => runWithOverrides(androidReleaser.validatePreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [flutterValidator],
            ),
          ).called(1);
        });
      });
    });

    group('validateArgs', () {
      group('when split-per-abi is true', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          when(() => argResults['split-per-abi']).thenReturn(true);
        });

        test('exits with code 69', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.validateArgs),
            exitsWithCode(ExitCode.unavailable),
          );
        });
      });

      group('when arguments are valid', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          when(() => argResults['split-per-abi']).thenReturn(false);
        });

        test('returns normally', () {
          expect(
            () => runWithOverrides(androidReleaser.validateArgs),
            returnsNormally,
          );
        });
      });
    });

    group('buildReleaseArtifacts', () {});

    group('getReleaseVersion', () {});

    group('uploadReleaseArtifacts', () {});
  });
}
