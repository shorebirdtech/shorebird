import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AndroidPatcher, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Doctor doctor;
    late Directory projectRoot;
    late FlavorValidator flavorValidator;
    late ShorebirdLogger logger;
    late PatchDiffChecker patchDiffChecker;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    late AndroidPatcher patcher;

    File patchArtifactForArch(Arch arch, {String? flavor}) {
      return File(
        p.join(
          projectRoot.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          flavor != null ? '${flavor}Release' : 'release',
          'out',
          'lib',
          arch.androidBuildPath,
          'libapp.so',
        ),
      );
    }

    void setUpProjectRootArtifacts({String? flavor}) {
      for (final arch in Arch.values) {
        patchArtifactForArch(arch, flavor: flavor)
          ..createSync(recursive: true)
          ..writeAsStringSync(arch.arch);
      }
    }

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          shorebirdAndroidArtifactsRef.overrideWith(
            () => shorebirdAndroidArtifacts,
          ),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(const AndroidArchiveDiffer());
      registerFallbackValue(Directory(''));
      registerFallbackValue(FakeReleaseArtifact());
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      doctor = MockDoctor();
      flavorValidator = MockFlavorValidator();
      patchDiffChecker = MockPatchDiffChecker();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults.options).thenReturn([]);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      patcher = AndroidPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('primaryReleaseArtifactArch', () {
      test('is "aab"', () {
        expect(patcher.primaryReleaseArtifactArch, equals('aab'));
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(
          () => doctor.androidCommandValidators,
        ).thenReturn([flavorValidator]);
        when(flavorValidator.validate).thenAnswer((_) async => []);
      });

      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
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
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
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
              validators: [flavorValidator],
            ),
          ).called(1);
        });
      });
    });

    group('assertUnpatchableDiffs', () {
      const diffStatus = DiffStatus(
        hasAssetChanges: false,
        hasNativeChanges: false,
      );

      setUp(() {
        when(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: any(named: 'localArchive'),
            releaseArchive: any(named: 'releaseArchive'),
            archiveDiffer: any(named: 'archiveDiffer'),
            allowAssetChanges: any(named: 'allowAssetChanges'),
            allowNativeChanges: any(named: 'allowNativeChanges'),
          ),
        ).thenAnswer((_) async => diffStatus);
      });

      test('forwards result from patchDiffChecker', () async {
        final result = await runWithOverrides(
          () => patcher.assertUnpatchableDiffs(
            releaseArtifact: FakeReleaseArtifact(),
            releaseArchive: File(''),
            patchArchive: File(''),
          ),
        );
        expect(result, equals(diffStatus));
        verify(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArchive: any(named: 'localArchive'),
            releaseArchive: any(named: 'releaseArchive'),
            archiveDiffer: any(named: 'archiveDiffer'),
            allowAssetChanges: any(named: 'allowAssetChanges'),
            allowNativeChanges: any(named: 'allowNativeChanges'),
          ),
        ).called(1);
      });
    });

    group('buildPatchArtifact', () {
      final flutterVersion = Version(3, 10, 6);
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';
      late File aabFile;

      setUp(() {
        aabFile = File('');
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
        when(
          () => shorebirdFlutter.getVersion(),
        ).thenAnswer((_) async => flutterVersion);
        when(
          () => artifactBuilder.buildAppBundle(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
            base64PublicKey: any(named: 'base64PublicKey'),
          ),
        ).thenAnswer((_) async => aabFile);
      });

      // See https://github.com/shorebirdtech/updater/issues/211
      group('when flutter version contains updater issue 211', () {
        setUp(() {
          setUpProjectRootArtifacts();
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 24, 1));
        });

        test('warns user of potential patch issues', () async {
          await runWithOverrides(patcher.buildPatchArtifact);

          verify(
            () => logger.warn(AndroidPatcher.updaterPatchErrorWarning),
          ).called(1);
        });
      });

      group('when flutter version does not contain updater issue 211', () {
        setUp(() {
          setUpProjectRootArtifacts();
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 24, 2));
        });

        test('does not warn user of potential patch issues', () async {
          await runWithOverrides(patcher.buildPatchArtifact);

          verifyNever(
            () => logger.warn(AndroidPatcher.updaterPatchErrorWarning),
          );
        });
      });

      group('when build fails', () {
        final exception = ArtifactBuildException('error');

        setUp(() {
          when(
            () => artifactBuilder.buildAppBundle(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              targetPlatforms: any(named: 'targetPlatforms'),
              args: any(named: 'args'),
              base64PublicKey: any(named: 'base64PublicKey'),
            ),
          ).thenThrow(exception);
        });

        test('throws exception', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            throwsA(exception),
          );
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
            () => logger.info('''
Please run `shorebird cache clean` and try again. If the issue persists, please
file a bug report at https://github.com/shorebirdtech/shorebird/issues/new.

Looked in:
  - build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib
  - build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib
  - build/app/intermediates/stripped_native_libs/release/out/lib
  - build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib'''),
          ).called(1);
        });
      });

      group('when releaseVersion is provided', () {
        setUp(setUpProjectRootArtifacts);

        test('forwards --build-name and --build-number to builder', () async {
          await runWithOverrides(
            () => patcher.buildPatchArtifact(releaseVersion: '1.2.3+4'),
          );
          verify(
            () => artifactBuilder.buildAppBundle(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              args: any(
                named: 'args',
                that: containsAll(['--build-name=1.2.3', '--build-number=4']),
              ),
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
              () => artifactBuilder.buildAppBundle(args: ['--verbose']),
            ).called(1);
          });
        });

        group('when the key pair is provided', () {
          setUp(() {
            when(
              () => codeSigner.base64PublicKey(any()),
            ).thenReturn('public_key_encoded');
          });

          test('calls buildIpa with the provided key', () async {
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
            ).thenReturn(true);

            final key = createTempFile('public.der')
              ..writeAsStringSync('public_key');

            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(key.path);
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(key.path);
            await runWithOverrides(patcher.buildPatchArtifact);

            verify(
              () => artifactBuilder.buildAppBundle(
                args: any(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: 'public_key_encoded',
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
        podfileLockHash: null,
        canSideload: true,
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
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
          ),
        ).thenAnswer((_) async => File(''));
      });

      group('when release artifact fails to download', () {
        setUp(() {
          when(
            () => artifactManager.downloadWithProgressUpdates(
              any(),
              message: any(named: 'message'),
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
          setUp(() {
            final privateKey = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'test-private.pem',
              ),
            )..createSync();

            when(
              () => argResults[CommonArguments.privateKeyArg.name],
            ).thenReturn(privateKey.path);

            when(
              () => codeSigner.sign(
                message: any(named: 'message'),
                privateKeyPemFile: any(named: 'privateKeyPemFile'),
              ),
            ).thenAnswer((invocation) {
              final message = invocation.namedArguments[#message] as String;
              return '$message-signature';
            });
          });

          test(
            'returns patch artifact bundles with proper hash signatures',
            () async {
              final result = await runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: 'appId',
                  releaseId: 0,
                  releaseArtifact: File('release.aab'),
                ),
              );

              // Hash the patch artifacts and append '-signature' to get the
              // expected signatures, per the mock of [codeSigner.sign] above.
              final expectedSignatures = Arch.values
                  .map(patchArtifactForArch)
                  .map((f) => sha256.convert(f.readAsBytesSync()).toString())
                  .map((hash) => '$hash-signature')
                  .toList();

              final signatures = result.values
                  .map((bundle) => bundle.hashSignature)
                  .toList();
              expect(signatures, equals(expectedSignatures));
            },
          );
        });

        group('when artifacts download takes longer than provided timeout', () {
          setUp(() {
            when(
              () => artifactManager.downloadWithProgressUpdates(
                any(),
                message: any(named: 'message'),
              ),
            ).thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              return File('');
            });
          });

          test('prints message directing users to github issue', () async {
            await runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: 'appId',
                releaseId: 0,
                releaseArtifact: File('release.aab'),
                downloadMessageTimeout: const Duration(milliseconds: 50),
              ),
            );

            verify(
              () => logger.info(
                any(
                  that: contains(
                    'https://github.com/shorebirdtech/shorebird/issues/2532',
                  ),
                ),
              ),
            ).called(1);
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
        },
      );
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

    group('updatedCreatePatchMetadata', () {
      const allowAssetDiffs = false;
      const allowNativeDiffs = true;
      const flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b';
      const operatingSystem = 'Mac OS X';
      const operatingSystemVersion = '10.15.7';

      test('returns correct metadata', () async {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: allowAssetDiffs,
          hasAssetChanges: false,
          usedIgnoreNativeChangesFlag: allowNativeDiffs,
          hasNativeChanges: false,
          inferredReleaseVersion: false,
          environment: BuildEnvironmentMetadata(
            flutterRevision: flutterRevision,
            operatingSystem: operatingSystem,
            operatingSystemVersion: operatingSystemVersion,
            shorebirdVersion: packageVersion,
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          ),
        );

        expect(
          runWithOverrides(() => patcher.updatedCreatePatchMetadata(metadata)),
          completion(metadata),
        );
      });
    });
  });
}
