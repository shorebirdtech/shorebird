import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AarPatcher, () {
    const packageName = 'com.example.my_flutter_module';
    const buildNumber = '1.0';

    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Directory projectRoot;
    late ShorebirdLogger logger;
    late PatchDiffChecker patchDiffChecker;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    late AarPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          shorebirdAndroidArtifactsRef.overrideWith(
            () => shorebirdAndroidArtifacts,
          ),
        },
      );
    }

    File patchArtifactForArch(Directory root, Arch arch, {String? flavor}) {
      return File(p.join(root.path, 'jni', arch.androidBuildPath, 'libapp.so'));
    }

    void setUpExtractedAarDirectory(Directory root) {
      for (final arch in Arch.values) {
        patchArtifactForArch(root, arch)
          ..createSync(recursive: true)
          ..writeAsStringSync(arch.arch);
      }
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
      patchDiffChecker = MockPatchDiffChecker();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults['build-number']).thenReturn('1.0');
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);

      when(() => shorebirdEnv.androidPackageName).thenReturn(packageName);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      patcher = AarPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('buildNumber', () {
      setUp(() {
        when(() => argResults['build-number']).thenReturn(buildNumber);
      });

      test('is the value of the build-number argument', () {
        expect(patcher.buildNumber, buildNumber);
      });
    });

    group('releaseType', () {
      test('is aar', () {
        expect(patcher.releaseType, ReleaseType.aar);
      });
    });

    group('primaryReleaseArtifactArch', () {
      test('is aar', () {
        expect(patcher.primaryReleaseArtifactArch, equals('aar'));
      });
    });

    group('assertPreconditions', () {
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

        group('when androidPackageName is null', () {
          setUp(() {
            when(() => shorebirdEnv.androidPackageName).thenReturn(null);
          });

          test('logs error and exits with code 64', () async {
            await expectLater(
              () => runWithOverrides(patcher.assertPreconditions),
              exitsWithCode(ExitCode.config),
            );
            verify(
              () =>
                  logger.err('Could not find androidPackage in pubspec.yaml.'),
            ).called(1);
          });
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
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';

      setUp(() {
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
      });

      group('when build fails', () {
        final exception = ArtifactBuildException('error');

        setUp(() {
          when(
            () => artifactBuilder.buildAar(
              buildNumber: any(named: 'buildNumber'),
              args: any(named: 'args'),
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

      group('when build succeeds', () {
        setUp(() {
          when(
            () => artifactBuilder.buildAar(
              buildNumber: any(named: 'buildNumber'),
              args: any(named: 'args'),
              base64PublicKey: any(named: 'base64PublicKey'),
            ),
          ).thenAnswer((_) async => {});
        });

        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['android', '--verbose']);
          });

          test('returns the aar artifact file', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);

            expect(artifact, isA<File>());
            expect(
              artifact.path,
              endsWith(
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
              ),
            );

            verify(
              () => artifactBuilder.buildAar(
                buildNumber: buildNumber,
                args: ['--verbose'],
              ),
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
              () => artifactBuilder.buildAar(
                buildNumber: buildNumber,
                args: any(named: 'args'),
                base64PublicKey: 'public_key_encoded',
              ),
            ).called(1);
          });
        });

        test('returns the aar artifact file', () async {
          final artifact = await runWithOverrides(patcher.buildPatchArtifact);

          expect(artifact, isA<File>());
          expect(
            artifact.path,
            endsWith(
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
            ),
          );

          verify(
            () => artifactBuilder.buildAar(
              buildNumber: buildNumber,
              args: any(named: 'args'),
            ),
          ).called(1);
        });
      });
    });

    group('createPatchArtifacts', () {
      const appId = 'appId';
      const arch = 'aarch64';
      const releaseId = 1;
      const releaseArtifact = ReleaseArtifact(
        id: 0,
        releaseId: releaseId,
        arch: arch,
        platform: ReleasePlatform.android,
        hash: '#',
        size: 42,
        url: 'https://example.com',
        podfileLockHash: null,
        canSideload: true,
      );

      late File releaseArtifactFile;
      late Directory extractedAarDirectory;

      setUp(() {
        releaseArtifactFile = File('');
        when(
          () => artifactManager.downloadFile(any()),
        ).thenAnswer((_) async => releaseArtifactFile);

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

        extractedAarDirectory = Directory.systemTemp.createTempSync();
        setUpExtractedAarDirectory(extractedAarDirectory);
        when(
          () => shorebirdAndroidArtifacts.extractAar(
            packageName: any(named: 'packageName'),
            buildNumber: any(named: 'buildNumber'),
            unzipFn: any(named: 'unzipFn'),
          ),
        ).thenAnswer((_) async => extractedAarDirectory);

        when(
          () => artifactManager.createDiff(
            patchArtifactPath: any(named: 'patchArtifactPath'),
            releaseArtifactPath: any(named: 'releaseArtifactPath'),
          ),
        ).thenAnswer((_) async {
          final diffPath = File(
            p.join(Directory.systemTemp.createTempSync().path, 'diff'),
          )..createSync();
          return diffPath.path;
        });
      });

      group('when release artifact download fails', () {
        final exception = Exception('error');
        setUp(() {
          when(() => artifactManager.downloadFile(any())).thenThrow(exception);
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifactFile,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('Exception: error')).called(1);
        });
      });

      group('when diff creation fails', () {
        setUp(() {
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
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifactFile,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('Exception: error')).called(1);
        });
      });

      group('when successful', () {
        test('returns map of archs to patch artifacts', () async {
          final patchArtifacts = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
            ),
          );

          expect(patchArtifacts, hasLength(3));
          expect(
            patchArtifacts.keys,
            containsAll([Arch.arm32, Arch.arm64, Arch.x86_64]),
          );
          expect(
            patchArtifacts.values,
            everyElement(isA<PatchArtifactBundle>()),
          );
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
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                ),
              );

              // Hash the patch artifacts and append '-signature' to get the
              // expected signatures, per the mock of [codeSigner.sign] above.
              final expectedSignatures =
                  Arch.values
                      .map(
                        (arch) =>
                            patchArtifactForArch(extractedAarDirectory, arch),
                      )
                      .map(
                        (f) => sha256.convert(f.readAsBytesSync()).toString(),
                      )
                      .map((hash) => '$hash-signature')
                      .toList();

              final signatures =
                  result.values.map((bundle) => bundle.hashSignature).toList();
              expect(signatures, equals(expectedSignatures));
            },
          );
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      test('throws UnimplementedError', () {
        expect(
          () => patcher.extractReleaseVersionFromArtifact(File('')),
          throwsUnimplementedError,
        );
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
