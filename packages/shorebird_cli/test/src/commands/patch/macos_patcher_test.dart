import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
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
  group(MacosPatcher, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Ditto ditto;
    late Doctor doctor;
    late EngineConfig engineConfig;
    late Directory projectRoot;
    late Directory appDirectory;
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
    late MacosPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          dittoRef.overrideWith(() => ditto),
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
      registerFallbackValue(const AppleArchiveDiffer());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.macos);
      registerFallbackValue(ShorebirdArtifact.genSnapshotMacosArm64);
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      ditto = MockDitto();
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

      when(() => argResults.options).thenReturn([]);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

      when(
        () => ditto.archive(
          source: any(named: 'source'),
          destination: any(named: 'destination'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => ditto.extract(
          source: any(named: 'source'),
          destination: any(named: 'destination'),
        ),
      ).thenAnswer((_) async {});

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(
        () => shorebirdEnv.buildDirectory,
      ).thenReturn(Directory(p.join(projectRoot.path, 'build')));
      when(
        () => shorebirdEnv.flutterRevision,
      ).thenReturn('5c1dcc19ebcee3565c65262dd95970186e4d81cc');

      appDirectory = Directory(
        p.join(
          projectRoot.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Release',
          'my.app',
        ),
      )..createSync(recursive: true);
      when(
        () => artifactManager.getMacOSAppDirectory(),
      ).thenReturn(appDirectory);

      patcher = MacosPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('primaryReleaseArtifactArch', () {
      test('is "app"', () {
        expect(patcher.primaryReleaseArtifactArch, 'app');
      });
    });

    group('releaseType', () {
      test('is ReleaseType.macos', () {
        expect(patcher.releaseType, ReleaseType.macos);
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(() => doctor.macosCommandValidators).thenReturn([flavorValidator]);
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

    group('assertUnpatchableDiffs', () {
      group('when no native changes are detected', () {
        const noChangeDiffStatus = DiffStatus(
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
              confirmNativeChanges: false,
            ),
          ).thenAnswer((_) async => noChangeDiffStatus);
        });

        test('returns diff status from patchDiffChecker', () async {
          final diffStatus = await runWithOverrides(
            () => patcher.assertUnpatchableDiffs(
              releaseArtifact: FakeReleaseArtifact(),
              releaseArchive: File(''),
              patchArchive: File(''),
            ),
          );
          expect(diffStatus, equals(noChangeDiffStatus));
          verifyNever(
            () => logger.warn(
              '''Your macos/Podfile.lock is different from the one used to build the release.''',
            ),
          );
        });
      });

      group('when native changes are detected', () {
        const nativeChangeDiffStatus = DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: true,
        );

        late String podfileLockHash;

        setUp(() {
          when(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArchive: any(named: 'localArchive'),
              releaseArchive: any(named: 'releaseArchive'),
              archiveDiffer: any(named: 'archiveDiffer'),
              allowAssetChanges: any(named: 'allowAssetChanges'),
              allowNativeChanges: any(named: 'allowNativeChanges'),
              confirmNativeChanges: false,
            ),
          ).thenAnswer((_) async => nativeChangeDiffStatus);

          const podfileLockContents = 'lock file';
          podfileLockHash =
              sha256.convert(utf8.encode(podfileLockContents)).toString();
          final podfileLockFile =
              File(
                  p.join(
                    Directory.systemTemp.createTempSync().path,
                    'Podfile.lock',
                  ),
                )
                ..createSync(recursive: true)
                ..writeAsStringSync(podfileLockContents);

          when(
            () => shorebirdEnv.macosPodfileLockFile,
          ).thenReturn(podfileLockFile);
        });

        group('when release has podspec lock hash', () {
          group('when release podspec lock hash matches patch', () {
            late final releaseArtifact = ReleaseArtifact(
              id: 0,
              releaseId: 0,
              arch: 'aarch64',
              platform: ReleasePlatform.macos,
              hash: '#',
              size: 42,
              url: 'https://example.com',
              podfileLockHash: podfileLockHash,
              canSideload: true,
            );

            test('does not warn of native changes', () async {
              final diffStatus = await runWithOverrides(
                () => patcher.assertUnpatchableDiffs(
                  releaseArtifact: releaseArtifact,
                  releaseArchive: File(''),
                  patchArchive: File(''),
                ),
              );
              expect(diffStatus, equals(nativeChangeDiffStatus));
              verifyNever(
                () => logger.warn(
                  '''Your macos/Podfile.lock is different from the one used to build the release.''',
                ),
              );
            });
          });

          group('when release podspec lock hash does not match patch', () {
            const releaseArtifact = ReleaseArtifact(
              id: 0,
              releaseId: 0,
              arch: 'aarch64',
              platform: ReleasePlatform.macos,
              hash: '#',
              size: 42,
              url: 'https://example.com',
              podfileLockHash: 'podfile-lock-hash',
              canSideload: true,
            );

            group('when native diffs are allowed', () {
              setUp(() {
                when(() => argResults['allow-native-diffs']).thenReturn(true);
              });

              test(
                'logs warning, does not prompt for confirmation to proceed',
                () async {
                  final diffStatus = await runWithOverrides(
                    () => patcher.assertUnpatchableDiffs(
                      releaseArtifact: releaseArtifact,
                      releaseArchive: File(''),
                      patchArchive: File(''),
                    ),
                  );
                  expect(diffStatus, equals(nativeChangeDiffStatus));
                  verify(
                    () => logger.warn(
                      '''
Your macos/Podfile.lock is different from the one used to build the release.
This may indicate that the patch contains native changes, which cannot be applied with a patch. Proceeding may result in unexpected behavior or crashes.''',
                    ),
                  ).called(1);
                  verifyNever(() => logger.confirm(any()));
                },
              );
            });

            group('when native diffs are not allowed', () {
              group('when in an environment that accepts user input', () {
                setUp(() {
                  when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
                });

                group('when user opts to continue at prompt', () {
                  setUp(() {
                    when(() => logger.confirm(any())).thenReturn(true);
                  });

                  test('returns diff status from patchDiffChecker', () async {
                    final diffStatus = await runWithOverrides(
                      () => patcher.assertUnpatchableDiffs(
                        releaseArtifact: releaseArtifact,
                        releaseArchive: File(''),
                        patchArchive: File(''),
                      ),
                    );
                    expect(diffStatus, equals(nativeChangeDiffStatus));
                  });
                });

                group('when user aborts at prompt', () {
                  setUp(() {
                    when(() => logger.confirm(any())).thenReturn(false);
                  });

                  test('throws UserCancelledException', () async {
                    await expectLater(
                      () => runWithOverrides(
                        () => patcher.assertUnpatchableDiffs(
                          releaseArtifact: releaseArtifact,
                          releaseArchive: File(''),
                          patchArchive: File(''),
                        ),
                      ),
                      throwsA(isA<UserCancelledException>()),
                    );
                  });
                });
              });

              group(
                'when in an environment that does not accept user input',
                () {
                  setUp(() {
                    when(
                      () => shorebirdEnv.canAcceptUserInput,
                    ).thenReturn(false);
                  });

                  test('throws UnpatchableChangeException', () async {
                    await expectLater(
                      () => runWithOverrides(
                        () => patcher.assertUnpatchableDiffs(
                          releaseArtifact: releaseArtifact,
                          releaseArchive: File(''),
                          patchArchive: File(''),
                        ),
                      ),
                      throwsA(isA<UnpatchableChangeException>()),
                    );
                  });
                },
              );
            });
          });
        });

        group('when release does not have podspec lock hash', () {});
      });
    });

    group('buildPatchArtifact', () {
      const flutterVersionAndRevision = '3.27.0 (8495dee1fd)';

      setUp(() {
        when(
          () => ditto.archive(
            source: any(named: 'source'),
            destination: any(named: 'destination'),
          ),
        ).thenAnswer((invocation) async {
          File(
            invocation.namedArguments[#destination] as String,
          ).createSync(recursive: true);
        });

        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
        when(
          () => shorebirdFlutter.getVersion(),
        ).thenAnswer((_) async => Version(3, 27, 4));
      });

      group('when specified flutter version is less than minimum', () {
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
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 0, 0));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );

          verify(
            () => logger.err('''
macOS patches are not supported with Flutter versions older than $minimumSupportedMacosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}'''),
          ).called(1);
        });
      });

      group('when build fails with ProcessException', () {
        setUp(() {
          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenThrow(
            const ProcessException('flutter', [
              'build',
              'macos',
            ], 'Build failed'),
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
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenThrow(ArtifactBuildException('Build failed'));
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail('Failed to build macOS app'));
        });
      });

      group('when elf aot snapshot build fails', () {
        setUp(() {
          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer(
            (_) async =>
                MacosBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
            ),
          ).thenThrow(const FileSystemException('error'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail("FileSystemException: error, path = ''"));
        });
      });

      group('when build fails to produce arm64 aot snapshot', () {
        setUp(() {
          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer(
            (_) async =>
                MacosBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
              additionalArgs: any(named: 'additionalArgs'),
            ),
          ).thenAnswer((invocation) async {
            final file = File(
              invocation.namedArguments[#outFilePath] as String,
            );
            if (!file.path.contains('arm64')) {
              file.createSync(recursive: true);
            }
            return file;
          });
        });

        test('exits with code 70', () async {
          await expectLater(
            runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );
        });
      });

      group('when build fails to produce x64 aot snapshot', () {
        setUp(() {
          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer(
            (_) async =>
                MacosBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
              additionalArgs: any(named: 'additionalArgs'),
            ),
          ).thenAnswer((invocation) async {
            final file = File(
              invocation.namedArguments[#outFilePath] as String,
            );
            if (!file.path.contains('x64')) {
              file.createSync(recursive: true);
            }
            return file;
          });
        });

        test('exits with code 70', () async {
          await expectLater(
            runWithOverrides(patcher.buildPatchArtifact),
            exitsWithCode(ExitCode.software),
          );
        });
      });

      group('when --split-debug-info is specified', () {
        late Directory splitDebugInfo;

        setUp(() {
          final tempDir = Directory.systemTemp.createTempSync();
          splitDebugInfo = Directory(p.join(tempDir.path, 'debug'));
          when(
            () => argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
          ).thenReturn(true);
          when(
            () => argResults[CommonArguments.splitDebugInfoArg.name],
          ).thenReturn(splitDebugInfo.path);

          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer(
            (_) async =>
                MacosBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
              additionalArgs: any(named: 'additionalArgs'),
            ),
          ).thenAnswer((invocation) async {
            final file = File(
              invocation.namedArguments[#outFilePath] as String,
            );
            if (!file.path.contains('x64')) {
              file.createSync(recursive: true);
            }
            return file;
          });
        });

        test('creates the directory', () async {
          expect(splitDebugInfo.existsSync(), isFalse);

          try {
            await runWithOverrides(patcher.buildPatchArtifact);
          } on Exception catch (_) {
            // swallow exception
          }

          expect(splitDebugInfo.existsSync(), isTrue);
        });
      });

      group('when build succeeds', () {
        late File kernelFile;
        setUp(() {
          kernelFile = File(
            p.join(Directory.systemTemp.createTempSync().path, 'app.dill'),
          )..createSync(recursive: true);
          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              base64PublicKey: any(named: 'base64PublicKey'),
            ),
          ).thenAnswer((_) async => MacosBuildResult(kernelFile: kernelFile));
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
        });

        group('when flavor is provided', () {
          const flavor = 'my-flavor';

          setUp(() {
            patcher = MacosPatcher(
              argParser: argParser,
              argResults: argResults,
              flavor: flavor,
              target: null,
            );

            when(
              () => artifactManager.getMacOSAppDirectory(flavor: flavor),
            ).thenReturn(appDirectory);
          });

          test('builds with flavor', () async {
            await runWithOverrides(patcher.buildPatchArtifact);
            verify(
              () => artifactBuilder.buildMacos(
                codesign: any(named: 'codesign'),
                args: any(named: 'args'),
                flavor: flavor,
                target: any(named: 'target'),
              ),
            ).called(1);
            verify(
              () => artifactManager.getMacOSAppDirectory(flavor: flavor),
            ).called(1);
          });
        });

        group('when releaseVersion is provided', () {
          test('forwards --build-name and --build-number to builder', () async {
            await runWithOverrides(
              () => patcher.buildPatchArtifact(releaseVersion: '1.2.3+4'),
            );
            verify(
              () => artifactBuilder.buildMacos(
                flavor: any(named: 'flavor'),
                codesign: any(named: 'codesign'),
                target: any(named: 'target'),
                args: any(
                  named: 'args',
                  that: containsAll(['--build-name=1.2.3', '--build-number=4']),
                ),
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

          test('calls the buildMacos passing the key', () async {
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
              () => artifactBuilder.buildMacos(
                codesign: any(named: 'codesign'),
                args: any(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: 'public_key_encoded',
              ),
            ).called(1);
          });
        });

        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['macos', '--verbose']);
          });

          test('returns app zip', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);
            expect(p.basename(artifact.path), endsWith('.zip'));
            verify(
              () => artifactBuilder.buildMacos(
                codesign: any(named: 'codesign'),
                args: ['--verbose'],
              ),
            ).called(1);
          });
        });

        test('returns app zip', () async {
          final artifact = await runWithOverrides(patcher.buildPatchArtifact);
          expect(p.basename(artifact.path), endsWith('.zip'));
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
      const appId = 'appId';
      const releaseId = 1;
      const arm64ElfAotSnapshotFileName = 'out.arm64.aot';
      const x64ElfAotSnapshotFileName = 'out.x64.aot';
      late File releaseArtifactFile;

      setUp(() {
        // This method assumes that the patch artifact has already been built.
        File(
          p.join(projectRoot.path, 'build', arm64ElfAotSnapshotFileName),
        ).createSync(recursive: true);
        File(
          p.join(projectRoot.path, 'build', x64ElfAotSnapshotFileName),
        ).createSync(recursive: true);

        releaseArtifactFile = File(
          p.join(Directory.systemTemp.createTempSync().path, 'release.app'),
        )..createSync(recursive: true);

        when(
          () => ditto.extract(
            source: any(named: 'source'),
            destination: any(named: 'destination'),
          ),
        ).thenAnswer((invocation) async {
          final releaseAppDirectory = Directory(
            invocation.namedArguments[#destination] as String,
          )..createSync(recursive: true);
          Directory(
            p.join(
              releaseAppDirectory.path,
              'Contents',
              'Frameworks',
              'App.framework',
              'App',
            ),
          ).createSync(recursive: true);
        });

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

        when(() => engineConfig.localEngine).thenReturn(null);
      });

      test('returns artifact bundles for x86_64 and aarch64 archs', () async {
        final artifacts = await runWithOverrides(
          () => patcher.createPatchArtifacts(
            appId: appId,
            releaseId: releaseId,
            releaseArtifact: releaseArtifactFile,
          ),
        );

        expect(artifacts, hasLength(2));
        expect(artifacts.keys, containsAll([Arch.x86_64, Arch.arm64]));
        expect(artifacts[Arch.x86_64]!.hashSignature, isNull);

        verifyNever(
          () => codeSigner.sign(
            message: any(named: 'message'),
            privateKeyPemFile: any(named: 'privateKeyPemFile'),
          ),
        );
      });

      group('when generating a signed patch', () {
        setUp(() {
          when(
            () => argResults[CommonArguments.privateKeyArg.name],
          ).thenReturn(createTempFile('private.pem').path);

          when(
            () => codeSigner.sign(
              message: any(named: 'message'),
              privateKeyPemFile: any(named: 'privateKeyPemFile'),
            ),
          ).thenReturn('my-signature');
        });

        test('returns artifact bundles with non-null hash signature', () async {
          final artifacts = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
            ),
          );

          expect(artifacts, hasLength(2));
          expect(artifacts.keys, containsAll([Arch.x86_64, Arch.arm64]));
          expect(artifacts[Arch.x86_64]!.hashSignature, 'my-signature');
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      group('when app directory does not exist', () {
        setUp(() {
          when(() => artifactManager.getMacOSAppDirectory()).thenReturn(null);
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
              p.join(appDirectory.path, 'Contents', 'Info.plist'),
            ).deleteSync(recursive: true);
          } on Exception {
            // ignore
          }
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
          File(p.join(appDirectory.path, 'Contents', 'Info.plist'))
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
              any(that: startsWith('Failed to determine release version')),
            ),
          ).called(1);
        });
      });

      group('when Info.plist does exist', () {
        setUp(() {
          File(p.join(appDirectory.path, 'Contents', 'Info.plist'))
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

      test('returns correct metadata', () async {
        const metadata = CreatePatchMetadata(
          releasePlatform: ReleasePlatform.macos,
          usedIgnoreAssetChangesFlag: allowAssetDiffs,
          hasAssetChanges: true,
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
          runWithOverrides(() => patcher.updatedCreatePatchMetadata(metadata)),
          completion(
            const CreatePatchMetadata(
              releasePlatform: ReleasePlatform.macos,
              usedIgnoreAssetChangesFlag: allowAssetDiffs,
              hasAssetChanges: true,
              usedIgnoreNativeChangesFlag: allowNativeDiffs,
              hasNativeChanges: false,
              environment: BuildEnvironmentMetadata(
                flutterRevision: flutterRevision,
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                xcodeVersion: xcodeVersion,
                shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
              ),
            ),
          ),
        );
      });
    });
  }, testOn: 'mac-os');
}
