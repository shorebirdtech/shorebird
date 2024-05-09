import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(
    IosPatcher,
    () {
      late AotTools aotTools;
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
      late Doctor doctor;
      late EngineConfig engineConfig;
      late Directory flutterDirectory;
      late Directory projectRoot;
      late ShorebirdLogger logger;
      late OperatingSystemInterface operatingSystemInterface;
      late Platform platform;
      late Progress progress;
      late ShorebirdArtifacts shorebirdArtifacts;
      late ShorebirdFlutterValidator flutterValidator;
      late ShorebirdProcess shorebirdProcess;
      late ShorebirdEnv shorebirdEnv;
      late ShorebirdFlutter shorebirdFlutter;
      late ShorebirdValidator shorebirdValidator;
      late XcodeBuild xcodeBuild;
      late Ios ios;
      late IosPatcher patcher;

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
            iosRef.overrideWith(() => ios),
            loggerRef.overrideWith(() => logger),
            osInterfaceRef.overrideWith(() => operatingSystemInterface),
            platformRef.overrideWith(() => platform),
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
        registerFallbackValue(FakeArgResults());
        registerFallbackValue(Directory(''));
        registerFallbackValue(File(''));
        registerFallbackValue(ReleasePlatform.ios);
        registerFallbackValue(Uri.parse('https://example.com'));
        setExitFunctionForTests();
      });

      tearDownAll(restoreExitFunction);

      setUp(() {
        aotTools = MockAotTools();
        argResults = MockArgResults();
        artifactBuilder = MockArtifactBuilder();
        artifactManager = MockArtifactManager();
        codePushClientWrapper = MockCodePushClientWrapper();
        doctor = MockDoctor();
        engineConfig = MockEngineConfig();
        ios = MockIos();
        operatingSystemInterface = MockOperatingSystemInterface();
        platform = MockPlatform();
        progress = MockProgress();
        projectRoot = Directory.systemTemp.createTempSync();
        logger = MockShorebirdLogger();
        shorebirdArtifacts = MockShorebirdArtifacts();
        shorebirdProcess = MockShorebirdProcess();
        shorebirdEnv = MockShorebirdEnv();
        flutterValidator = MockShorebirdFlutterValidator();
        shorebirdFlutter = MockShorebirdFlutter();
        shorebirdValidator = MockShorebirdValidator();
        xcodeBuild = MockXcodeBuild();

        when(() => argResults['build-number']).thenReturn('1.0');

        when(() => logger.progress(any())).thenReturn(progress);

        when(
          () => shorebirdEnv.getShorebirdProjectRoot(),
        ).thenReturn(projectRoot);

        when(() => ios.exportOptionsPlistFromArgs(any())).thenReturn(File(''));

        patcher = IosPatcher(
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      group('archiveDiffer', () {
        test('is an IosArchiveDiffer', () {
          expect(patcher.archiveDiffer, isA<IosArchiveDiffer>());
        });
      });

      group('primaryReleaseArtifactArch', () {
        test('is "xcarchive"', () {
          expect(patcher.primaryReleaseArtifactArch, 'xcarchive');
        });
      });

      group('releaseType', () {
        test('is ReleaseType.ios', () {
          expect(patcher.releaseType, ReleaseType.ios);
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
          ).thenReturn([flutterValidator]);
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
                validators: any(
                  named: 'validators',
                ),
              ),
            ).thenThrow(exception);
          });

          test('exits with code 70', () async {
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
                validators: [flutterValidator],
                supportedOperatingSystems: {Platform.macOS},
              ),
            ).called(1);
          });
        });
      });

      group('buildPatchArtifact', () {
        const flutterVersionAndRevision = '3.10.6 (83305b5088)';

        setUp(() {
          when(
            () => shorebirdFlutter.getVersionAndRevision(),
          ).thenAnswer((_) async => flutterVersionAndRevision);
        });

        group('when exportOptionsPlist fails', () {
          setUp(() {
            when(() => ios.exportOptionsPlistFromArgs(any())).thenThrow(
              const FileSystemException('error'),
            );
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(patcher.buildPatchArtifact),
              exitsWithCode(ExitCode.usage),
            );
          });
        });

        group('when build fails with ProcessException', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIpa(
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                codesign: any(named: 'codesign'),
                argResultsRest: any(named: 'argResultsRest'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenThrow(
              const ProcessException(
                'flutter',
                ['build', 'ipa'],
                'Build failed',
              ),
            );
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(patcher.buildPatchArtifact),
              exitsWithCode(ExitCode.software),
            );

            verify(() => progress.fail('Failed to build: Build failed'));
          });
        });

        group('when build fails with ArtifactBuildException', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIpa(
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                codesign: any(named: 'codesign'),
                argResultsRest: any(named: 'argResultsRest'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenThrow(
              ArtifactBuildException('Build failed'),
            );
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(patcher.buildPatchArtifact),
              exitsWithCode(ExitCode.software),
            );

            verify(() => progress.fail('Failed to build IPA'));
          });
        });

        group('when elf aot snapshot build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIpa(
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                codesign: any(named: 'codesign'),
                argResultsRest: any(named: 'argResultsRest'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenAnswer((_) async {});
            when(() => artifactManager.newestAppDill()).thenReturn(File(''));
            when(
              () => artifactBuilder.buildElfAotSnapshot(
                appDillPath: any(named: 'appDillPath'),
                outFilePath: any(named: 'outFilePath'),
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
          setUp(() {
            when(
              () => artifactBuilder.buildIpa(
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                codesign: any(named: 'codesign'),
                argResultsRest: any(named: 'argResultsRest'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenAnswer((_) async {});
            when(() => artifactManager.getXcarchiveDirectory()).thenReturn(
              Directory(
                p.join(
                  projectRoot.path,
                  'build',
                  'ios',
                  'framework',
                  'Release',
                  'App.xcframework',
                ),
              )..createSync(recursive: true),
            );
            when(() => artifactManager.newestAppDill()).thenReturn(File(''));
            when(
              () => artifactBuilder.buildElfAotSnapshot(
                appDillPath: any(named: 'appDillPath'),
                outFilePath: any(named: 'outFilePath'),
              ),
            ).thenAnswer(
              (invocation) async =>
                  File(invocation.namedArguments[#outFilePath] as String)
                    ..createSync(recursive: true),
            );
          });

          test('returns xcarchive zip', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);
            expect(p.basename(artifact.path), endsWith('.zip'));
          });
        });
      });

      group('createPatchArtifacts', () {
        const postLinkerFlutterRevision =
            'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
        const preLinkerFlutterRevision =
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
        );

        void setUpProjectRootArtifacts() {
          // Create a second app.dill for coverage of newestAppDill file.
          File(
            p.join(
              projectRoot.path,
              '.dart_tool',
              'flutter_build',
              'subdir',
              'app.dill',
            ),
          ).createSync(recursive: true);
          File(
            p.join(projectRoot.path, '.dart_tool', 'flutter_build', 'app.dill'),
          ).createSync(recursive: true);
          File(p.join(projectRoot.path, 'build', elfAotSnapshotFileName))
              .createSync(
            recursive: true,
          );
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'framework',
              'Release',
              'App.xcframework',
            ),
          ).createSync(
            recursive: true,
          );
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'framework',
              'Release',
              'App.xcframework',
              'Products',
              'Applications',
              'Runner.app',
            ),
          ).createSync(
            recursive: true,
          );
          File(
            p.join(projectRoot.path, 'build', linkFileName),
          ).createSync(recursive: true);
        }

        setUp(() {
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
          when(() => artifactManager.getXcarchiveDirectory()).thenReturn(
            Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'framework',
                'Release',
                'App.xcframework',
              ),
            ),
          );
          when(
            () => artifactManager.getIosAppDirectory(
              xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
            ),
          ).thenReturn(projectRoot);
          when(() => engineConfig.localEngine).thenReturn(null);
        });

        group('when xcarchive does not exist', () {
          setUp(() {
            when(
              () => artifactManager.getXcarchiveDirectory(),
            ).thenReturn(null);
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
          });
        });

        group('when release artifact download fails', () {
          setUp(() {
            when(
              () => artifactManager.downloadFile(any()),
            ).thenThrow(Exception('Failed to download release artifact'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
          });
        });

        group('when release artifact does not exist', () {
          setUp(() {
            when(
              () => artifactManager.downloadFile(any()),
            ).thenAnswer((_) async => File(''));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => progress.fail(
                'Exception: Failed to download release artifact',
              ),
            );
          });
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
                dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
              ),
            ).thenAnswer((_) async => linkPercentage);
            when(() => artifactManager.newestAppDill()).thenReturn(File(''));
            when(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
              ),
            ).thenReturn(
              Directory(p.join(projectRoot.path, 'build', 'ios')),
            );
            when(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
              ),
            ).thenReturn(Directory(p.join(projectRoot.path, 'build', 'ios')));
            when(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
              ),
            ).thenReturn(
              Directory(
                p.join(
                  projectRoot.path,
                  'build',
                  'ios',
                  'framework',
                  'Release',
                  'App.xcframework',
                  'Products',
                  'Applications',
                  'Runner.app',
                ),
              ),
            );
            when(() => shorebirdEnv.flutterRevision)
                .thenReturn(postLinkerFlutterRevision);
            when(
              () => shorebirdArtifacts.getArtifactPath(
                artifact: ShorebirdArtifact.analyzeSnapshot,
              ),
            ).thenReturn(analyzeSnapshotFile.path);
            when(
              () => shorebirdArtifacts.getArtifactPath(
                artifact: ShorebirdArtifact.genSnapshot,
              ),
            ).thenReturn(genSnapshotFile.path);
          });

          group('when linking fails', () {
            group('when .app does not exist', () {
              setUp(() {
                when(
                  () => artifactManager.getIosAppDirectory(
                    xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
                  ),
                ).thenReturn(null);
              });

              test('logs error and exits with code 70', () async {
                await expectLater(
                  () => runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                    ),
                  ),
                  exitsWithCode(ExitCode.software),
                );

                verify(
                  () => logger.err(
                    any(
                      that: startsWith(
                        'Unable to find release artifact .app directory',
                      ),
                    ),
                  ),
                ).called(1);
              });
            });

            group('when aot snapshot does not exist', () {
              test('logs error and exits with code 70', () async {
                await expectLater(
                  () => runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
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
                    artifact: ShorebirdArtifact.analyzeSnapshot,
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
                    ),
                  ),
                  exitsWithCode(ExitCode.software),
                );

                verify(
                  () => logger.err('Unable to find analyze_snapshot at '),
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
                    dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
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

              group('when isLinkDebugInfoSupported', () {
                setUp(() {
                  when(() => argResults['debug-linker']).thenReturn(true);
                  when(
                    aotTools.isLinkDebugInfoSupported,
                  ).thenAnswer((_) async => true);
                });

                test('dumps debug info', () async {
                  await runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                    ),
                  );
                  verify(
                    () => aotTools.link(
                      base: any(named: 'base'),
                      patch: any(named: 'patch'),
                      analyzeSnapshot: any(named: 'analyzeSnapshot'),
                      genSnapshot: any(named: 'genSnapshot'),
                      kernel: any(named: 'kernel'),
                      outputPath: any(named: 'outputPath'),
                      workingDirectory: any(named: 'workingDirectory'),
                      dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
                    ),
                  ).called(1);
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
        setUp(() {
          when(() => artifactManager.getXcarchiveDirectory()).thenReturn(
            Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'framework',
                'Release',
                'App.xcframework',
              ),
            ),
          );
        });

        group('when xcarchive directory does not exist', () {
          setUp(() {
            when(
              () => artifactManager.getXcarchiveDirectory(),
            ).thenReturn(null);
          });

          test('exit with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.extractReleaseVersionFromArtifact(File('')),
              ),
              exitsWithCode(ExitCode.software),
            );
          });
        });

        group('when Info.plist does not exist', () {
          setUp(() {
            try {
              File(
                p.join(
                  projectRoot.path,
                  'build',
                  'ios',
                  'framework',
                  'Release',
                  'App.xcframework',
                  'Info.plist',
                ),
              ).deleteSync(recursive: true);
            } catch (_) {}
          });

          test('exit with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.extractReleaseVersionFromArtifact(File('')),
              ),
              exitsWithCode(ExitCode.software),
            );
          });
        });

        group('when empty Info.plist does exist', () {
          setUp(() {
            File(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'framework',
                'Release',
                'App.xcframework',
                'Info.plist',
              ),
            )
              ..createSync(recursive: true)
              ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict></dict>
</plist>
''');
          });

          test('exits with code 70 and logs error', () async {
            await expectLater(
              runWithOverrides(
                () => patcher.extractReleaseVersionFromArtifact(File('')),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => logger.err(
                any(
                  that: startsWith('Failed to determine release version'),
                ),
              ),
            ).called(1);
          });
        });

        group('when Info.plist does exist', () {
          setUp(() {
            File(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'framework',
                'Release',
                'App.xcframework',
                'Info.plist',
              ),
            )
              ..createSync(recursive: true)
              ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/Runner.app</string>
		<key>Architectures</key>
		<array>
			<string>arm64</string>
		</array>
		<key>CFBundleIdentifier</key>
		<string>com.shorebird.timeShift</string>
		<key>CFBundleShortVersionString</key>
		<string>1.2.3</string>
		<key>CFBundleVersion</key>
		<string>1</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>Name</key>
	<string>Runner</string>
	<key>SchemeName</key>
	<string>Runner</string>
</dict>
</plist>
''');
          });

          test('returns correct version', () async {
            await expectLater(
              runWithOverrides(
                () => patcher.extractReleaseVersionFromArtifact(File('')),
              ),
              completion('1.2.3+1'),
            );
          });
        });
      });

      group('createPatchMetadata', () {
        const allowAssetDiffs = false;
        const allowNativeDiffs = true;
        const operatingSystem = 'Mac OS X';
        const operatingSystemVersion = '10.15.7';
        const xcodeVersion = '11';

        setUp(() {
          when(
            () => argResults['allow-asset-diffs'],
          ).thenReturn(allowAssetDiffs);
          when(
            () => argResults['allow-native-diffs'],
          ).thenReturn(allowNativeDiffs);
          when(() => platform.operatingSystem).thenReturn(operatingSystem);
          when(
            () => platform.operatingSystemVersion,
          ).thenReturn(operatingSystemVersion);

          when(
            () => xcodeBuild.version(),
          ).thenAnswer((_) async => xcodeVersion);
        });

        group('when linker is not enabled', () {
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
                  releasePlatform: ReleasePlatform.ios,
                  usedIgnoreAssetChangesFlag: allowAssetDiffs,
                  hasAssetChanges: diffStatus.hasAssetChanges,
                  usedIgnoreNativeChangesFlag: allowNativeDiffs,
                  hasNativeChanges: diffStatus.hasNativeChanges,
                  linkPercentage: null,
                  environment: const BuildEnvironmentMetadata(
                    operatingSystem: operatingSystem,
                    operatingSystemVersion: operatingSystemVersion,
                    shorebirdVersion: packageVersion,
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
                  releasePlatform: ReleasePlatform.ios,
                  usedIgnoreAssetChangesFlag: allowAssetDiffs,
                  hasAssetChanges: diffStatus.hasAssetChanges,
                  usedIgnoreNativeChangesFlag: allowNativeDiffs,
                  hasNativeChanges: diffStatus.hasNativeChanges,
                  linkPercentage: linkPercentage,
                  environment: const BuildEnvironmentMetadata(
                    operatingSystem: operatingSystem,
                    operatingSystemVersion: operatingSystemVersion,
                    shorebirdVersion: packageVersion,
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
