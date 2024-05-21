import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AndroidPatcher, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late Doctor doctor;
    late Platform platform;
    late Directory projectRoot;
    late ShorebirdLogger logger;
    late Progress progress;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    late AndroidPatcher patcher;

    void setUpProjectRootArtifacts({String? flavor}) {
      for (final archMetadata in Arch.values) {
        final artifactPath = p.join(
          projectRoot.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          flavor != null ? '${flavor}Release' : 'release',
          'out',
          'lib',
          archMetadata.androidBuildPath,
          'libapp.so',
        );
        File(artifactPath).createSync(recursive: true);
      }
    }

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
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

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(Uri.parse('https://example.com'));
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      platform = MockPlatform();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults.rest).thenReturn([]);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      patcher = AndroidPatcher(
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('archiveDiffer', () {
      test('is an AndroidArchiveDiffer', () {
        expect(patcher.archiveDiffer, isA<AndroidArchiveDiffer>());
      });
    });

    group('primaryReleaseArtifactArch', () {
      test('is "aab"', () {
        expect(patcher.primaryReleaseArtifactArch, equals('aab'));
      });
    });

    group('assertArgsAreValid', () {
      test('does nothing', () async {
        await expectLater(patcher.assertArgsAreValid(), completes);
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(() => doctor.androidCommandValidators)
            .thenReturn([flutterValidator]);
        when(flutterValidator.validate).thenAnswer((_) async => []);
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
            () => runWithOverrides(patcher.assertPreconditions),
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
            () => runWithOverrides(patcher.assertPreconditions),
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

    group('buildPatchArtifact', () {
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';
      late File aabFile;

      setUp(() {
        aabFile = File('');
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
        when(
          () => artifactBuilder.buildAppBundle(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => aabFile);
      });

      group('when build fails', () {
        final exception = ArtifactBuildException('error');

        setUp(() {
          when(
            () => artifactBuilder.buildAppBundle(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              args: any(named: 'args'),
            ),
          ).thenThrow(exception);
          when(() => logger.progress(any())).thenReturn(progress);
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('error')).called(1);
        });
      });

      group('when patch artifacts cannot be found', () {
        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );

          verify(
            () => logger.err('Cannot find patch build artifacts.'),
          ).called(1);
          verify(
            () => logger.info(
              '''
Please run `shorebird cache clean` and try again. If the issue persists, please
file a bug report at https://github.com/shorebirdtech/shorebird/issues/new.

Looked in:
  - build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib
  - build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib
  - build/app/intermediates/stripped_native_libs/release/out/lib
  - build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib''',
            ),
          ).called(1);
        });
      });

      group('when build succeeds', () {
        setUp(setUpProjectRootArtifacts);

        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['android', '--verbose']);
          });

          test('returns the aab file', () async {
            final result = await runWithOverrides(patcher.buildPatchArtifact);
            expect(result, equals(aabFile));
            verify(
              () => artifactBuilder.buildAppBundle(
                args: ['--verbose'],
              ),
            ).called(1);
          });
        });

        test('returns the aab file', () async {
          final result = await runWithOverrides(patcher.buildPatchArtifact);
          expect(result, equals(aabFile));
        });
      });
    });

    group('createPatchArtifacts', () {
      const arch = 'aarch64';
      const releaseArtifact = ReleaseArtifact(
        id: 0,
        releaseId: 0,
        arch: arch,
        platform: ReleasePlatform.android,
        hash: '#',
        size: 42,
        url: 'https://example.com',
      );

      setUp(() {
        when(
          () => codePushClientWrapper.getReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            architectures: any(named: 'architectures'),
            platform: any(named: 'platform'),
          ),
        ).thenAnswer(
          (_) async => {
            Arch.arm32: releaseArtifact,
            Arch.arm64: releaseArtifact,
            Arch.x86_64: releaseArtifact,
          },
        );
        when(() => artifactManager.downloadFile(any()))
            .thenAnswer((_) async => File(''));
      });

      group('when release artifact fails to download', () {
        setUp(() {
          when(
            () => artifactManager.downloadFile(any()),
          ).thenThrow(Exception('error'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'appId',
                releaseId: 0,
                releaseArtifact: File('release.aab'),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('Exception: error')).called(1);
        });
      });

      group('when unable to find patch build artifacts', () {
        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'appId',
                releaseId: 0,
                releaseArtifact: File('release.aab'),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => logger.err('Could not find patch artifacts')).called(1);
        });
      });

      group('when unable to create diffs', () {
        setUp(() {
          setUpProjectRootArtifacts();

          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenThrow(Exception('error'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'appId',
                releaseId: 0,
                releaseArtifact: File('release.aab'),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('Exception: error')).called(1);
        });
      });

      group('when patch artifacts successfully created', () {
        setUp(() {
          setUpProjectRootArtifacts();
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenAnswer((_) async {
            final tempDir = Directory.systemTemp.createTempSync();
            final diffPath = p.join(tempDir.path, 'diff');
            File(diffPath)
              ..createSync()
              ..writeAsStringSync('test');
            return diffPath;
          });
        });

        test('returns patch artifact bundles', () async {
          final result = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: 'appId',
              releaseId: 0,
              releaseArtifact: File('release.aab'),
            ),
          );

          expect(result, hasLength(Arch.values.length));
          for (final bundle in result.values) {
            expect(bundle.hashSignature, isNull);
          }
        });

        group('when a private key is provided', () {
          const testPrivateKeyContent = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7dlJZ1VAkZVhA
eqkr7HUUPdwvnMDAUWJxb4Rcf8KfcjcCjSwOu5KvjcOGhq5XaOecXiincBpGoEx0
KkX/6l4aiKFxq1dqdoLluXRnXfOMEBym+QNEU7Jbh/imUE2ikFvcbDEf0b3xVBc1
BIXazI9/teTD9073tp5SVjSKRpVyHotl1WdNxJFRnKj7stgpJDi7FWQmqDYr2w3v
W1QePxjxWqztQrhC+p5mhQ8BVqctaPJzUq70PXpIAHebXhMhDfYHZQmngY0ipwLC
A73aUs5RPaHAX4sKSaic6xjsA1fo1h9nL+Fn/Bhu2Ykkl4dXbMJAmmjcPuhnCUZ+
HdoUNqGZAgMBAAECggEAPZWfdDepvms01On3DaD+zYmM/m9Gu2eBKbbzCthF/c+t
1r6+DJD+nYG7DETOnZSvEiW0wV0IpM8gjsEcgfhiteDQ+ODLNQR9+C422YZ57jeU
0h3YPugoHf3LaAfVmWRHaWB5uvRSrCduAFLeDoVJVzFQWDi0zphF5tK/K/YIPpbN
tOJXoQ3P1jsrPlBCXbssskOOdZniciBDdGIFZab1gFnU4IrEtznYDOZi1cg4lzW8
4e8Ah/fwWLuwD76cUIRkgduKKTzLvPns+dOWv7IwMZeaGh8ORkne/dd8fKEB2Zaq
WePF2W0NFw/GCvn2ye5Ykow9RH32JAqqj26FnWrdqQKBgQDwLwo70kPQCBtHtPYU
OoDd1BFxNSgXEQUOGs9PSPkmqWZ4jDV+dgA5gVWu37HC2PC+p97FzUi7l2wZMHB3
JvxZ0yT2XzkjIXhBp38trNhk5BNLOCJoq/DzP95w6VCD6CQJl+/HA6Cud+2KmUgt
BfJO44EWEXq96CTkpsIoksfeGwKBgQDHzoOtwrumP3U7+G7mJx92O7IcWw8pi2HD
j+Xprels7Tz7oj0tOIIScD/0MEG4vx9VHZGz2RGED+qQjebUwHy04rSZ0yCeBBBp
HiAzlXXY47cHWHMQeCuzM+1DAyHzMi1joy7jkCaLCtDrLX6n0jCtPEWU5NbTjZpS
W9oNTNLqWwKBgQDWoPKAKpE2oUffeDI+OVlW4V8Ezv+YPTlLNWHz873RcqeDKafT
7hadTJoIvxTWjY30kYZdM+i+2b1bdRHLKCdxDWGGV+lzH0GbSdY4NrDY14b2PJ9i
8eNLO9PHCndMqHErsX4vVWqM/dZjeD4rHZk+Lcb4tX39nij5upreLuwz6QKBgAZB
jRXvtvhpnD4YdUB3kSCeleEVaNAgMRtycfxzGY/zjalDVy8HSetR4G7A5A3ozg5Y
Mquy7D16Uhncl5GpxT3Uq1r1pVvNPMZNzyxOTbZQyvZL6q5lVNjzk0Y53uJCe/FW
tq0hYlOQLyJt9j1C84s5C+SxlZhiIqbZgWZRNXlpAoGAa4QMZ3Oh1LuGZZw7tmh5
9u5R4XkBT1qA1Rcs13LW78OseBTeEuFf60iW2RR7F++wLj3Ab1qFIIp2N4fiA+GL
LirrX00cYQ78wxBU9ssdcB3Hd30ldGLu32O1++d4rFKGIxjA0quBseUfuXogRDSb
GdoVu5jMWQ9F15r/po9RSk8=
-----END PRIVATE KEY-----
''';

          late File privateKey;

          setUp(() {
            privateKey = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'test-private.pem',
              ),
            )..writeAsStringSync(testPrivateKeyContent);

            when(() => argResults['private-key-path'])
                .thenReturn(privateKey.path);
          });

          test('returns patch artifact bundles with proper hash signatures',
              () async {
            final result = await runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'appId',
                releaseId: 0,
                releaseArtifact: File('release.aab'),
              ),
            );

            const expectedSignatures = [
              'WmH5nujxcAwu3gy0VHmAG8ezx6hemJIWBe6RcSS9S7LHa+kVv6NtZZ48m0777LVjqYQT/EBYx9vVchgQtQSpm9Lr+IsfSYzcHqIwi8BfGls+4FzVCSDbH7Fdpug8KfWrcRdBa3hGueqf0mIbpfS3GebW+2bmkZAv6GSHiit0qNkCub5/B7JJyOVpZ4z7NTK9K6XRTmU3X8kWFPiMMYxh8asc6NWQC1vsbYDEraKuCAPAZs+uBpefnq29/HN1ZbwaRHDXvZVA8Q1m6vFz4Lu8S/2WToBhUv4YQQjHv8ZMoWGwGV83VUkFNkwBvp9ouZBOL0jT3740coCJeUU/Zx2sKw==',
              'WmH5nujxcAwu3gy0VHmAG8ezx6hemJIWBe6RcSS9S7LHa+kVv6NtZZ48m0777LVjqYQT/EBYx9vVchgQtQSpm9Lr+IsfSYzcHqIwi8BfGls+4FzVCSDbH7Fdpug8KfWrcRdBa3hGueqf0mIbpfS3GebW+2bmkZAv6GSHiit0qNkCub5/B7JJyOVpZ4z7NTK9K6XRTmU3X8kWFPiMMYxh8asc6NWQC1vsbYDEraKuCAPAZs+uBpefnq29/HN1ZbwaRHDXvZVA8Q1m6vFz4Lu8S/2WToBhUv4YQQjHv8ZMoWGwGV83VUkFNkwBvp9ouZBOL0jT3740coCJeUU/Zx2sKw==',
              'WmH5nujxcAwu3gy0VHmAG8ezx6hemJIWBe6RcSS9S7LHa+kVv6NtZZ48m0777LVjqYQT/EBYx9vVchgQtQSpm9Lr+IsfSYzcHqIwi8BfGls+4FzVCSDbH7Fdpug8KfWrcRdBa3hGueqf0mIbpfS3GebW+2bmkZAv6GSHiit0qNkCub5/B7JJyOVpZ4z7NTK9K6XRTmU3X8kWFPiMMYxh8asc6NWQC1vsbYDEraKuCAPAZs+uBpefnq29/HN1ZbwaRHDXvZVA8Q1m6vFz4Lu8S/2WToBhUv4YQQjHv8ZMoWGwGV83VUkFNkwBvp9ouZBOL0jT3740coCJeUU/Zx2sKw==',
            ];

            final signatures =
                result.values.map((bundle) => bundle.hashSignature).toList();
            expect(signatures, equals(expectedSignatures));
          });
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      setUp(() {
        when(
          () => shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
            any(),
          ),
        ).thenAnswer((_) async => '1.0.0');
      });

      test(
          '''returns value of shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle''',
          () async {
        expect(
          await runWithOverrides(
            () => patcher.extractReleaseVersionFromArtifact(File('')),
          ),
          equals('1.0.0'),
        );
      });
    });

    group('patchArtifactForDiffCheck', () {
      late File aabFile;
      setUp(() {
        aabFile = File('');
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(aabFile);
      });
    });

    group('createPatchMetadata', () {
      const allowAssetDiffs = false;
      const allowNativeDiffs = true;
      const operatingSystem = 'Mac OS X';
      const operatingSystemVersion = '10.15.7';

      setUp(() {
        when(() => argResults['allow-asset-diffs']).thenReturn(allowAssetDiffs);
        when(
          () => argResults['allow-native-diffs'],
        ).thenReturn(allowNativeDiffs);
        when(() => platform.operatingSystem).thenReturn(operatingSystem);
        when(
          () => platform.operatingSystemVersion,
        ).thenReturn(operatingSystemVersion);
      });

      test('returns correct metadata', () async {
        final diffStatus = DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        );

        final metadata = await runWithOverrides(
          () => patcher.createPatchMetadata(diffStatus),
        );

        expect(
          metadata,
          equals(
            CreatePatchMetadata(
              releasePlatform: ReleasePlatform.android,
              usedIgnoreAssetChangesFlag: allowAssetDiffs,
              hasAssetChanges: diffStatus.hasAssetChanges,
              usedIgnoreNativeChangesFlag: allowNativeDiffs,
              hasNativeChanges: diffStatus.hasNativeChanges,
              linkPercentage: null,
              environment: const BuildEnvironmentMetadata(
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                xcodeVersion: null,
              ),
            ),
          ),
        );
      });
    });
  });
}
