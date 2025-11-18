import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
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
  group(IosFrameworkPatcher, () {
    late AotTools aotTools;
    late Apple apple;
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Doctor doctor;
    late Directory flutterDirectory;
    late Directory projectRoot;
    late EngineConfig engineConfig;
    late FlavorValidator flavorValidator;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late PatchDiffChecker patchDiffChecker;
    late Progress progress;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late XcodeBuild xcodeBuild;
    late IosFrameworkPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          appleRef.overrideWith(() => apple),
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => engineConfig),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          xcodeBuildRef.overrideWith(() => xcodeBuild),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(const AppleArchiveDiffer());
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ShorebirdArtifact.genSnapshotIos);
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      apple = MockApple();
      aotTools = MockAotTools();
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      doctor = MockDoctor();
      engineConfig = MockEngineConfig();
      flavorValidator = MockFlavorValidator();
      operatingSystemInterface = MockOperatingSystemInterface();
      patchDiffChecker = MockPatchDiffChecker();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      xcodeBuild = MockXcodeBuild();

      when(() => argParser.options).thenReturn({});

      when(() => argResults['build-number']).thenReturn('1.0');
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.buildDirectory,
      ).thenReturn(Directory(p.join(projectRoot.path, 'build')));
      when(() => shorebirdEnv.iosSupplementDirectory).thenReturn(
        Directory(p.join(projectRoot.path, 'build', 'shorebird', 'ios')),
      );
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      patcher = IosFrameworkPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('primaryReleaseArtifactArch', () {
      test('is "xcframework"', () {
        expect(patcher.primaryReleaseArtifactArch, 'xcframework');
      });
    });

    group('supplementaryReleaseArtifactArch', () {
      test('is "ios_framework_supplement"', () {
        expect(
          patcher.supplementaryReleaseArtifactArch,
          'ios_framework_supplement',
        );
      });
    });

    group('releaseType', () {
      test('is ReleaseType.iosFramework', () {
        expect(patcher.releaseType, ReleaseType.iosFramework);
      });
    });

    group('linkPercentage', () {
      group('when linking has not occurred', () {
        test('returns null', () {
          expect(patcher.linkPercentage, isNull);
        });
      });

      group('when linking has occurred', () {
        const linkPercentage = 42.1337;

        setUp(() {
          patcher.lastBuildLinkPercentage = linkPercentage;
        });

        test('returns correct link percentage', () {
          expect(patcher.linkPercentage, equals(linkPercentage));
        });
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(() => doctor.iosCommandValidators).thenReturn([flavorValidator]);
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
              supportedOperatingSystems: any(
                named: 'supportedOperatingSystems',
              ),
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
              supportedOperatingSystems: {Platform.macOS},
            ),
          ).called(1);
        });
      });
    });

    group('assertArgsAreValid', () {
      group('when release-version is not provided', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(false);
        });

        test('exits with code 64', () async {
          await expectLater(
            () => runWithOverrides(patcher.assertArgsAreValid),
            exitsWithCode(ExitCode.usage),
          );
        });
      });

      group('when arguments are valid', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(true);
        });

        test('returns normally', () {
          expect(
            () => runWithOverrides(patcher.assertArgsAreValid),
            returnsNormally,
          );
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
        final exception = ArtifactBuildException('Build failed');
        setUp(() {
          when(
            () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
          ).thenThrow(exception);
        });

        test('throws exception', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            throwsA(exception),
          );
        });
      });

      group('when elf aot snapshot build fails', () {
        const exception = FileSystemException('error');
        setUp(() {
          when(
            () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
          ).thenAnswer(
            (_) async => AppleBuildResult(kernelFile: File('app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
              additionalArgs: any(named: 'additionalArgs'),
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
        late File kernelFile;
        setUp(() {
          kernelFile = File(
            p.join(Directory.systemTemp.createTempSync().path, 'app.dill'),
          )..createSync(recursive: true);
          when(
            () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
          ).thenAnswer((_) async => AppleBuildResult(kernelFile: kernelFile));
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
              additionalArgs: any(named: 'additionalArgs'),
            ),
          ).thenAnswer(
            (invocation) async =>
                File(invocation.namedArguments[#outFilePath] as String)
                  ..createSync(recursive: true),
          );

          Directory(
            p.join(projectRoot.path, ArtifactManager.appXcframeworkName),
          ).createSync(recursive: true);
          when(
            () => artifactManager.getAppXcframeworkDirectory(),
          ).thenReturn(projectRoot);
        });

        group('when --split-debug-info is provided', () {
          final tempDir = Directory.systemTemp.createTempSync();
          final splitDebugInfoPath = p.join(tempDir.path, 'symbols');
          final splitDebugInfoFile = File(
            p.join(splitDebugInfoPath, 'app.ios-arm64.symbols'),
          );
          setUp(() {
            when(
              () =>
                  argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
            ).thenReturn(true);
            when(
              () => argResults['split-debug-info'],
            ).thenReturn(splitDebugInfoPath);
          });

          test('forwards --split-debug-info to builder', () async {
            try {
              await runWithOverrides(patcher.buildPatchArtifact);
            } on Exception {
              // ignore
            }
            verify(
              () => artifactBuilder.buildElfAotSnapshot(
                appDillPath: any(named: 'appDillPath'),
                outFilePath: any(named: 'outFilePath'),
                genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
                additionalArgs: [
                  '--dwarf-stack-traces',
                  '--resolve-dwarf-paths',
                  '--save-debugging-info=${splitDebugInfoFile.path}',
                ],
              ),
            ).called(1);
          });
        });

        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['ios', '--verbose']);
          });

          test('returns zipped xcframework', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);
            expect(p.basename(artifact.path), equals('App.xcframework.zip'));
            verify(
              () => artifactBuilder.buildIosFramework(args: ['--verbose']),
            ).called(1);
          });
        });

        group('when the key pair is provided', () {
          setUp(() {
            when(
              () => codeSigner.base64PublicKey(any()),
            ).thenReturn('public_key_encoded');
            when(
              () => artifactBuilder.buildIosFramework(
                args: any(named: 'args'),
                base64PublicKey: any(named: 'base64PublicKey'),
              ),
            ).thenAnswer((_) async => AppleBuildResult(kernelFile: kernelFile));
          });

          test('calls the buildIosFramework passing the key', () async {
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
            ).thenReturn(true);

            final key = createTempFile('public.pem')
              ..writeAsStringSync('public_key');

            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(key.path);
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(key.path);
            await runWithOverrides(patcher.buildPatchArtifact);

            verify(
              () => artifactBuilder.buildIosFramework(
                args: any(named: 'args'),
                base64PublicKey: 'public_key_encoded',
              ),
            ).called(1);
          });
        });

        test('returns zipped xcframework', () async {
          final artifact = await runWithOverrides(patcher.buildPatchArtifact);
          expect(p.basename(artifact.path), equals('App.xcframework.zip'));
        });

        test('copies app.dill to build directory', () async {
          final copiedKernelFile = File(
            p.join(projectRoot.path, 'build', 'app.dill'),
          );
          expect(copiedKernelFile.existsSync(), isFalse);
          await runWithOverrides(patcher.buildPatchArtifact);
          expect(copiedKernelFile.existsSync(), isTrue);
        });
      });
    });

    group('createPatchArtifacts', () {
      const postLinkerFlutterRevision = // cspell: disable-next-line
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
      const preLinkerFlutterRevision = // cspell: disable-next-line
          '83305b5088e6fe327fb3334a73ff190828d85713';
      const appId = 'appId';
      const arch = 'aarch64';
      const releaseId = 1;
      const linkFileName = 'out.vmcode';
      const elfAotSnapshotFileName = 'out.aot';
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
      late File supplementArtifactFile;

      void setUpProjectRootArtifacts() {
        File(
          p.join(projectRoot.path, 'build', elfAotSnapshotFileName),
        ).createSync(recursive: true);
        File(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'framework',
            'Release',
            'App.xcframework',
            'ios-arm64',
            'App.framework',
            'App',
          ),
        ).createSync(recursive: true);
        File(
          p.join(projectRoot.path, 'build', linkFileName),
        ).createSync(recursive: true);
        File(
          p.join(projectRoot.path, 'build', 'ios', 'shorebird', 'App.ct.link'),
        ).createSync(recursive: true);
        File(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'shorebird',
            'App.class_table.json',
          ),
        ).createSync(recursive: true);
      }

      setUp(() {
        releaseArtifactFile = File(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'release.xcframework',
          ),
        )..createSync(recursive: true);
        supplementArtifactFile = File(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'ios_framework_supplement.zip',
          ),
        )..createSync(recursive: true);

        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenAnswer((_) async => releaseArtifact);
        when(() => artifactManager.downloadFile(any())).thenAnswer((_) async {
          final tempDirectory = Directory.systemTemp.createTempSync();
          final file = File(p.join(tempDirectory.path, 'libapp.so'))
            ..createSync();
          return file;
        });
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {
          final zipFile = invocation.namedArguments[#zipFile] as File;
          final outDir =
              invocation.namedArguments[#outputDirectory] as Directory;
          File(
            p.join(outDir.path, '${p.basename(zipFile.path)}.zip'),
          ).createSync();
        });
        when(() => engineConfig.localEngine).thenReturn(null);
      });

      group('when uses linker', () {
        const linkPercentage = 50.0;
        late File analyzeSnapshotFile;
        late File genSnapshotFile;

        setUp(() {
          final shorebirdRoot = Directory.systemTemp.createTempSync();
          flutterDirectory = Directory(
            p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
          );
          genSnapshotFile = File(
            p.join(
              flutterDirectory.path,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'ios-release',
              'gen_snapshot_arm64',
            ),
          );
          analyzeSnapshotFile = File(
            p.join(
              flutterDirectory.path,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'ios-release',
              'analyze_snapshot_arm64',
            ),
          )..createSync(recursive: true);

          when(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              aotOutputFile: any(named: 'aotOutputFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              vmCodeFile: any(named: 'vmCodeFile'),
            ),
          ).thenAnswer(
            (_) async => LinkResult.success(linkPercentage: linkPercentage),
          );
          when(
            aotTools.isGeneratePatchDiffBaseSupported,
          ).thenAnswer((_) async => false);
          when(
            () => shorebirdEnv.flutterRevision,
          ).thenReturn(postLinkerFlutterRevision);
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotIos,
            ),
          ).thenReturn(analyzeSnapshotFile.path);
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotIos,
            ),
          ).thenReturn(genSnapshotFile.path);
        });

        group('when generate patch diff base is supported', () {
          setUp(() {
            when(
              () => aotTools.isGeneratePatchDiffBaseSupported(),
            ).thenAnswer((_) async => true);
            when(
              () => aotTools.generatePatchDiffBase(
                analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                releaseSnapshot: any(named: 'releaseSnapshot'),
              ),
            ).thenAnswer((_) async => File(''));
          });

          group('when we fail to generate patch diff base', () {
            setUp(() {
              when(
                () => aotTools.generatePatchDiffBase(
                  analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                  releaseSnapshot: any(named: 'releaseSnapshot'),
                ),
              ).thenThrow(Exception('oops'));

              setUpProjectRootArtifacts();
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

              verify(() => progress.fail('Exception: oops')).called(1);
            });
          });

          group('when linking and patch diff generation succeeds', () {
            const diffPath = 'path/to/diff';

            setUp(() {
              when(
                () => artifactManager.createDiff(
                  releaseArtifactPath: any(named: 'releaseArtifactPath'),
                  patchArtifactPath: any(named: 'patchArtifactPath'),
                ),
              ).thenAnswer((_) async => diffPath);
              setUpProjectRootArtifacts();
            });

            test('calls runLinker with correct arguments', () async {
              await runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                ),
              );

              verify(
                () => apple.runLinker(
                  kernelFile: any(
                    named: 'kernelFile',
                    that: isA<File>().having(
                      (f) => f.path,
                      'path',
                      p.join(projectRoot.path, 'build', 'app.dill'),
                    ),
                  ),
                  aotOutputFile: any(
                    named: 'aotOutputFile',
                    that: isA<File>().having(
                      (f) => f.path,
                      'path',
                      p.join(projectRoot.path, 'build', 'out.aot'),
                    ),
                  ),
                  releaseArtifact: any(
                    named: 'releaseArtifact',
                    that: isA<File>().having(
                      (f) => f.path,
                      'path',
                      endsWith(p.join('ios-arm64', 'App.framework', 'App')),
                    ),
                  ),
                  vmCodeFile: any(
                    named: 'vmCodeFile',
                    that: isA<File>().having(
                      (f) => f.path,
                      'path',
                      p.join(projectRoot.path, 'build', 'out.vmcode'),
                    ),
                  ),
                  splitDebugInfoArgs: [],
                ),
              ).called(1);
            });

            test('returns linked patch artifact in patch bundle', () async {
              final patchBundle = await runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                ),
              );

              expect(patchBundle, hasLength(1));
              expect(
                patchBundle[Arch.arm64],
                isA<PatchArtifactBundle>().having(
                  (b) => b.path,
                  'path',
                  endsWith(diffPath),
                ),
              );
            });

            group('when class table link info & debug info are present', () {
              setUp(() {
                when(
                  () => artifactManager.extractZip(
                    zipFile: releaseArtifactFile,
                    outputDirectory: any(named: 'outputDirectory'),
                  ),
                ).thenAnswer((invocation) async {
                  final outDir =
                      invocation.namedArguments[#outputDirectory] as Directory;
                  File(
                    p.join(outDir.path, 'ios-arm64', 'App.framework', 'App'),
                  ).createSync(recursive: true);
                });
                when(
                  () => artifactManager.extractZip(
                    zipFile: supplementArtifactFile,
                    outputDirectory: any(named: 'outputDirectory'),
                  ),
                ).thenAnswer((invocation) async {
                  final outDir =
                      invocation.namedArguments[#outputDirectory] as Directory;
                  File(
                    p.join(outDir.path, 'App.ct.link'),
                  ).createSync(recursive: true);
                  File(
                    p.join(outDir.path, 'App.class_table.json'),
                  ).createSync(recursive: true);
                });
              });

              test('returns linked patch artifact in patch bundle', () async {
                final patchBundle = await runWithOverrides(
                  () => patcher.createPatchArtifacts(
                    appId: appId,
                    releaseId: releaseId,
                    releaseArtifact: releaseArtifactFile,
                    supplementArtifact: supplementArtifactFile,
                  ),
                );

                expect(patchBundle, hasLength(1));
                expect(
                  patchBundle[Arch.arm64],
                  isA<PatchArtifactBundle>().having(
                    (b) => b.path,
                    'path',
                    endsWith(diffPath),
                  ),
                );
              });
            });

            test('sets link percentage', () async {
              expect(patcher.linkPercentage, isNull);
              await runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                  supplementArtifact: supplementArtifactFile,
                ),
              );
              expect(patcher.linkPercentage, isNotNull);
            });

            group('when code signing the patch', () {
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
                '''returns patch artifact bundles with proper hash signatures''',
                () async {
                  final result = await runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                      releaseArtifact: releaseArtifactFile,
                    ),
                  );

                  // Hash the patch artifacts and append '-signature' to get the
                  // expected signatures, per the mock of [codeSigner.sign]
                  // above.
                  const expectedSignature =
                      '''e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855-signature''';

                  expect(
                    result.values.first.hashSignature,
                    equals(expectedSignature),
                  );
                },
              );
            });
          });
        });

        group('when linker reports snapshot version mismatch', () {
          setUp(() {
            when(
              () => apple.runLinker(
                kernelFile: any(named: 'kernelFile'),
                aotOutputFile: any(named: 'aotOutputFile'),
                releaseArtifact: any(named: 'releaseArtifact'),
                splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
                vmCodeFile: any(named: 'vmCodeFile'),
              ),
            ).thenAnswer(
              (_) async => LinkResult.failure(
                error: AotToolsExecutionFailure(
                  exitCode: ExitCode.software.code,
                  stdout: '',
                  stderr: 'Wrong full snapshot version, expected foo found bar',
                  command: 'aot_tools link',
                ),
              ),
            );
            when(
              () => aotTools.isGeneratePatchDiffBaseSupported(),
            ).thenAnswer((_) async => true);
            setUpProjectRootArtifacts();
          });

          test('falls back to an unlinked patch', () async {
            await expectLater(
              runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                  supplementArtifact: supplementArtifactFile,
                ),
              ),
              completes,
            );

            verifyNever(() => aotTools.isGeneratePatchDiffBaseSupported());
            verifyNever(
              () => aotTools.generatePatchDiffBase(
                analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                releaseSnapshot: any(named: 'releaseSnapshot'),
              ),
            );
            expect(patcher.linkPercentage, isNull);
          });
        });

        group('when generate patch diff base is not supported', () {
          setUp(() {
            when(
              aotTools.isGeneratePatchDiffBaseSupported,
            ).thenAnswer((_) async => false);
            setUpProjectRootArtifacts();
          });

          test('returns vmcode file as patch file', () async {
            final patchBundle = await runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifactFile,
              ),
            );

            expect(patchBundle, hasLength(1));
            expect(
              patchBundle[Arch.arm64],
              isA<PatchArtifactBundle>().having(
                (b) => b.path,
                'path',
                endsWith('out.vmcode'),
              ),
            );
          });
        });
      });

      group('when does not use linker', () {
        setUp(() {
          when(
            () => shorebirdEnv.flutterRevision,
          ).thenReturn(preLinkerFlutterRevision);
          when(
            () => aotTools.isGeneratePatchDiffBaseSupported(),
          ).thenAnswer((_) async => false);

          setUpProjectRootArtifacts();
        });

        test('returns base patch artifact in patch bundle', () async {
          final patchArtifacts = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
            ),
          );

          expect(patchArtifacts, hasLength(1));
          verifyNever(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              outputPath: any(named: 'outputPath'),
            ),
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
      const xcodeVersion = '11';

      setUp(() {
        when(() => xcodeBuild.version()).thenAnswer((_) async => xcodeVersion);
      });

      group('when linker is not enabled', () {
        test('returns correct metadata', () async {
          const metadata = CreatePatchMetadata(
            releasePlatform: ReleasePlatform.ios,
            usedIgnoreAssetChangesFlag: allowAssetDiffs,
            hasAssetChanges: true,
            usedIgnoreNativeChangesFlag: allowNativeDiffs,
            hasNativeChanges: true,
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
            runWithOverrides(
              () => patcher.updatedCreatePatchMetadata(metadata),
            ),
            completion(
              const CreatePatchMetadata(
                releasePlatform: ReleasePlatform.ios,
                usedIgnoreAssetChangesFlag: allowAssetDiffs,
                hasAssetChanges: true,
                usedIgnoreNativeChangesFlag: allowNativeDiffs,
                hasNativeChanges: true,
                inferredReleaseVersion: false,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                  xcodeVersion: xcodeVersion,
                ),
              ),
            ),
          );
        });
      });

      group('when linker is enabled', () {
        const linkPercentage = 100.0;
        const linkMetadata = {'link': 'metadata'};

        setUp(() {
          patcher
            ..lastBuildLinkPercentage = linkPercentage
            ..lastBuildLinkMetadata = linkMetadata;
        });

        test('returns correct metadata', () async {
          const metadata = CreatePatchMetadata(
            releasePlatform: ReleasePlatform.ios,
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
            runWithOverrides(
              () => patcher.updatedCreatePatchMetadata(metadata),
            ),
            completion(
              const CreatePatchMetadata(
                releasePlatform: ReleasePlatform.ios,
                usedIgnoreAssetChangesFlag: allowAssetDiffs,
                hasAssetChanges: false,
                usedIgnoreNativeChangesFlag: allowNativeDiffs,
                hasNativeChanges: false,
                inferredReleaseVersion: false,
                linkPercentage: linkPercentage,
                linkMetadata: linkMetadata,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                  xcodeVersion: xcodeVersion,
                ),
              ),
            ),
          );
        });
      });
    });
  }, testOn: 'mac-os');
}
