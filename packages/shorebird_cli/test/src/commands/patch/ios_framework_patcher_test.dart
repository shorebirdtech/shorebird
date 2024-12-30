import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
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
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(
    IosFrameworkPatcher,
    () {
      late AotTools aotTools;
      late ArgParser argParser;
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
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
            artifactBuilderRef.overrideWith(() => artifactBuilder),
            artifactManagerRef.overrideWith(() => artifactManager),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
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
        aotTools = MockAotTools();
        argParser = MockArgParser();
        argResults = MockArgResults();
        artifactBuilder = MockArtifactBuilder();
        artifactManager = MockArtifactManager();
        codePushClientWrapper = MockCodePushClientWrapper();
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
          when(
            () => doctor.iosCommandValidators,
          ).thenReturn([flavorValidator]);
        });

        group('when validation succeeds', () {
          setUp(() {
            when(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated: any(
                  named: 'checkUserIsAuthenticated',
                ),
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
                checkUserIsAuthenticated: any(
                  named: 'checkUserIsAuthenticated',
                ),
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
                checkUserIsAuthenticated:
                    any(named: 'checkUserIsAuthenticated'),
                checkShorebirdInitialized:
                    any(named: 'checkShorebirdInitialized'),
                validators: any(named: 'validators'),
                supportedOperatingSystems:
                    any(named: 'supportedOperatingSystems'),
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
            when(() => argResults.wasParsed('release-version'))
                .thenReturn(false);
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
            when(() => argResults.wasParsed('release-version'))
                .thenReturn(true);
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
          setUp(() {
            when(
              () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
            ).thenThrow(
              ArtifactBuildException('Build failed'),
            );
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(patcher.buildPatchArtifact),
              exitsWithCode(ExitCode.software),
            );

            verify(() => progress.fail('Build failed'));
          });
        });

        group('when elf aot snapshot build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
            ).thenAnswer(
              (_) async => IosFrameworkBuildResult(
                kernelFile: File('app.dill'),
              ),
            );
            when(
              () => artifactBuilder.buildElfAotSnapshot(
                appDillPath: any(named: 'appDillPath'),
                outFilePath: any(named: 'outFilePath'),
                genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
                additionalArgs: any(named: 'additionalArgs'),
              ),
            ).thenThrow(const FileSystemException('error'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(patcher.buildPatchArtifact),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => progress.fail("FileSystemException: error, path = ''"),
            );
          });
        });

        group('when build succeeds', () {
          late File kernelFile;
          setUp(() {
            kernelFile = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'app.dill',
              ),
            )..createSync(recursive: true);
            when(
              () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
            ).thenAnswer(
              (_) async => IosFrameworkBuildResult(kernelFile: kernelFile),
            );
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
                () => argResults.wasParsed(
                  CommonArguments.splitDebugInfoArg.name,
                ),
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
              final artifact = await runWithOverrides(
                patcher.buildPatchArtifact,
              );
              expect(p.basename(artifact.path), equals('App.xcframework.zip'));
              verify(
                () => artifactBuilder.buildIosFramework(
                  args: ['--verbose'],
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
          File(p.join(projectRoot.path, 'build', elfAotSnapshotFileName))
              .createSync(
            recursive: true,
          );
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
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'shorebird',
              'App.ct.link',
            ),
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
            File(p.join(outDir.path, '${p.basename(zipFile.path)}.zip'))
                .createSync();
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
              () => aotTools.link(
                base: any(named: 'base'),
                patch: any(named: 'patch'),
                analyzeSnapshot: any(named: 'analyzeSnapshot'),
                genSnapshot: any(named: 'genSnapshot'),
                kernel: any(named: 'kernel'),
                outputPath: any(named: 'outputPath'),
                workingDirectory: any(named: 'workingDirectory'),
                additionalArgs: any(named: 'additionalArgs'),
              ),
            ).thenAnswer((_) async => linkPercentage);
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

          group('when linking fails', () {
            group('when aot snapshot does not exist', () {
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

                verify(
                  () => logger.err(
                    any(that: startsWith('Unable to find patch AOT file at')),
                  ),
                ).called(1);
              });
            });

            group('when analyzeSnapshot binary does not exist', () {
              setUp(() {
                when(
                  () => shorebirdArtifacts.getArtifactPath(
                    artifact: ShorebirdArtifact.analyzeSnapshotIos,
                  ),
                ).thenReturn('');
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

                verify(
                  () => logger.err('Unable to find analyze_snapshot at '),
                ).called(1);
              });
            });

            group('when --split-debug-info is provided', () {
              final tempDirectory = Directory.systemTemp.createTempSync();
              final splitDebugInfoPath = p.join(tempDirectory.path, 'symbols');
              final splitDebugInfoFile = File(
                p.join(splitDebugInfoPath, 'app.ios-arm64.symbols'),
              );
              setUp(() {
                when(
                  () => argResults.wasParsed(
                    CommonArguments.splitDebugInfoArg.name,
                  ),
                ).thenReturn(true);
                when(
                  () => argResults[CommonArguments.splitDebugInfoArg.name],
                ).thenReturn(splitDebugInfoPath);
                setUpProjectRootArtifacts();
              });

              test('forwards correct args to linker', () async {
                try {
                  await runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                      releaseArtifact: releaseArtifactFile,
                    ),
                  );
                } on Exception {
                  // ignore
                }
                verify(
                  () => aotTools.link(
                    base: any(named: 'base'),
                    patch: any(named: 'patch'),
                    analyzeSnapshot: analyzeSnapshotFile.path,
                    genSnapshot: genSnapshotFile.path,
                    kernel: any(named: 'kernel'),
                    outputPath: any(named: 'outputPath'),
                    workingDirectory: any(named: 'workingDirectory'),
                    dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
                    additionalArgs: [
                      '--dwarf-stack-traces',
                      '--resolve-dwarf-paths',
                      '--save-debugging-info=${splitDebugInfoFile.path}',
                    ],
                  ),
                ).called(1);
              });
            });

            group('when call to aotTools.link fails', () {
              setUp(() {
                when(
                  () => aotTools.link(
                    base: any(named: 'base'),
                    patch: any(named: 'patch'),
                    analyzeSnapshot: any(named: 'analyzeSnapshot'),
                    genSnapshot: any(named: 'genSnapshot'),
                    kernel: any(named: 'kernel'),
                    outputPath: any(named: 'outputPath'),
                    workingDirectory: any(named: 'workingDirectory'),
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

                verify(
                  () => progress.fail(
                    'Failed to link AOT files: Exception: oops',
                  ),
                ).called(1);
              });
            });
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

              group('when class table link info is not present', () {
                setUp(() {
                  when(
                    () => artifactManager.extractZip(
                      zipFile: supplementArtifactFile,
                      outputDirectory: any(named: 'outputDirectory'),
                    ),
                  ).thenAnswer((invocation) async {});
                });

                test('exits with code 70', () async {
                  await expectLater(
                    () => runWithOverrides(
                      () => patcher.createPatchArtifacts(
                        appId: appId,
                        releaseId: releaseId,
                        releaseArtifact: releaseArtifactFile,
                        supplementArtifact: supplementArtifactFile,
                      ),
                    ),
                    exitsWithCode(ExitCode.software),
                  );

                  verify(
                    () => logger.err(
                      'Unable to find class table link info file',
                    ),
                  ).called(1);
                });
              });

              group('when debug info is missing', () {
                setUp(() {
                  when(
                    () => artifactManager.extractZip(
                      zipFile: supplementArtifactFile,
                      outputDirectory: any(named: 'outputDirectory'),
                    ),
                  ).thenAnswer((invocation) async {
                    final outDir = invocation.namedArguments[#outputDirectory]
                        as Directory;
                    File(
                      p.join(outDir.path, 'App.ct.link'),
                    ).createSync(recursive: true);
                  });
                });

                test('exits with code 70', () async {
                  await expectLater(
                    () => runWithOverrides(
                      () => patcher.createPatchArtifacts(
                        appId: appId,
                        releaseId: releaseId,
                        releaseArtifact: releaseArtifactFile,
                        supplementArtifact: supplementArtifactFile,
                      ),
                    ),
                    exitsWithCode(ExitCode.software),
                  );

                  verify(
                    () => logger.err(
                      'Unable to find class table link debug info file',
                    ),
                  ).called(1);
                });
              });

              group('when class table link info & debug info are present', () {
                setUp(() {
                  when(
                    () => artifactManager.extractZip(
                      zipFile: releaseArtifactFile,
                      outputDirectory: any(named: 'outputDirectory'),
                    ),
                  ).thenAnswer((invocation) async {
                    final outDir = invocation.namedArguments[#outputDirectory]
                        as Directory;
                    File(
                      p.join(
                        outDir.path,
                        'ios-arm64',
                        'App.framework',
                        'App',
                      ),
                    ).createSync(recursive: true);
                  });
                  when(
                    () => artifactManager.extractZip(
                      zipFile: supplementArtifactFile,
                      outputDirectory: any(named: 'outputDirectory'),
                    ),
                  ).thenAnswer((invocation) async {
                    final outDir = invocation.namedArguments[#outputDirectory]
                        as Directory;
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
          when(
            () => xcodeBuild.version(),
          ).thenAnswer((_) async => xcodeVersion);
        });

        group('when linker is not enabled', () {
          test('returns correct metadata', () async {
            const metadata = CreatePatchMetadata(
              releasePlatform: ReleasePlatform.ios,
              usedIgnoreAssetChangesFlag: allowAssetDiffs,
              hasAssetChanges: true,
              usedIgnoreNativeChangesFlag: allowNativeDiffs,
              hasNativeChanges: true,
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

          setUp(() {
            patcher.lastBuildLinkPercentage = linkPercentage;
          });

          test('returns correct metadata', () async {
            const metadata = CreatePatchMetadata(
              releasePlatform: ReleasePlatform.ios,
              usedIgnoreAssetChangesFlag: allowAssetDiffs,
              hasAssetChanges: false,
              usedIgnoreNativeChangesFlag: allowNativeDiffs,
              hasNativeChanges: false,
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
                  linkPercentage: linkPercentage,
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
    },
    testOn: 'mac-os',
  );
}
