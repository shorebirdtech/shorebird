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
import 'package:shorebird_cli/src/archive_analysis/ios_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
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
import 'package:shorebird_cli/src/logger.dart';
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
  group(
    IosPatcher,
    () {
      late AotTools aotTools;
      late ArgParser argParser;
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
      late CodeSigner codeSigner;
      late Doctor doctor;
      late EngineConfig engineConfig;
      late Directory flutterDirectory;
      late Directory projectRoot;
      late ShorebirdLogger logger;
      late OperatingSystemInterface operatingSystemInterface;
      late PatchDiffChecker patchDiffChecker;
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
            codeSignerRef.overrideWith(() => codeSigner),
            doctorRef.overrideWith(() => doctor),
            engineConfigRef.overrideWith(() => engineConfig),
            iosRef.overrideWith(() => ios),
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
        registerFallbackValue(FakeArgResults());
        registerFallbackValue(Directory(''));
        registerFallbackValue(File(''));
        registerFallbackValue(const IosArchiveDiffer());
        registerFallbackValue(ReleasePlatform.ios);
        registerFallbackValue(Uri.parse('https://example.com'));
      });

      setUp(() {
        aotTools = MockAotTools();
        argParser = MockArgParser();
        argResults = MockArgResults();
        artifactBuilder = MockArtifactBuilder();
        artifactManager = MockArtifactManager();
        codePushClientWrapper = MockCodePushClientWrapper();
        codeSigner = MockCodeSigner();
        doctor = MockDoctor();
        engineConfig = MockEngineConfig();
        ios = MockIos();
        operatingSystemInterface = MockOperatingSystemInterface();
        patchDiffChecker = MockPatchDiffChecker();
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

        when(() => argParser.options).thenReturn({});

        when(() => argResults.options).thenReturn([]);
        when(() => argResults.rest).thenReturn([]);
        when(() => argResults.wasParsed(any())).thenReturn(false);

        when(() => logger.progress(any())).thenReturn(progress);

        when(
          () => shorebirdEnv.getShorebirdProjectRoot(),
        ).thenReturn(projectRoot);

        when(() => ios.exportOptionsPlistFromArgs(any())).thenReturn(File(''));

        when(aotTools.isLinkDebugInfoSupported).thenAnswer((_) async => false);

        patcher = IosPatcher(
          argParser: argParser,
          argResults: argResults,
          flavor: null,
          target: null,
        );
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
                '''Your ios/Podfile.lock is different from the one used to build the release.''',
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
            final podfileLockFile = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'Podfile.lock',
              ),
            )
              ..createSync(recursive: true)
              ..writeAsStringSync(podfileLockContents);

            when(() => shorebirdEnv.podfileLockFile)
                .thenReturn(podfileLockFile);
          });

          group('when release has podspec lock hash', () {
            group('when release podspec lock hash matches patch', () {
              late final releaseArtifact = ReleaseArtifact(
                id: 0,
                releaseId: 0,
                arch: 'aarch64',
                platform: ReleasePlatform.ios,
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
                    '''Your ios/Podfile.lock is different from the one used to build the release.''',
                  ),
                );
              });
            });

            group('when release podspec lock hash does not match patch', () {
              const releaseArtifact = ReleaseArtifact(
                id: 0,
                releaseId: 0,
                arch: 'aarch64',
                platform: ReleasePlatform.ios,
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
Your ios/Podfile.lock is different from the one used to build the release.
This may indicate that the patch contains native changes, which cannot be applied with a patch. Proceeding may result in unexpected behavior or crashes.''',
                    ),
                  ).called(1);
                  verifyNever(() => logger.confirm(any()));
                });
              });

              group('when native diffs are not allowed', () {
                group('when in an environment that accepts user input', () {
                  setUp(() {
                    when(() => shorebirdEnv.canAcceptUserInput)
                        .thenReturn(true);
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

                group('when in an environment that does not accept user input',
                    () {
                  setUp(() {
                    when(() => shorebirdEnv.canAcceptUserInput)
                        .thenReturn(false);
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
                });
              });
            });
          });

          group('when release does not have podspec lock hash', () {});
        });
      });

      group('buildPatchArtifact', () {
        const flutterVersionAndRevision = '3.22.2 (83305b5088)';
        setUp(() {
          when(
            () => shorebirdFlutter.getVersionAndRevision(),
          ).thenAnswer((_) async => flutterVersionAndRevision);
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 22, 2));
        });

        group('when specified flutter version is less than minimum', () {
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
              () => logger.err(
                '''
iOS patches are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''',
              ),
            ).called(1);
          });
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
                args: any(named: 'args'),
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
                args: any(named: 'args'),
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
                args: any(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenAnswer(
              (_) async =>
                  IpaBuildResult(kernelFile: File('/path/to/app.dill')),
            );
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
          late File kernelFile;
          setUp(() {
            kernelFile = File(
              p.join(Directory.systemTemp.createTempSync().path, 'app.dill'),
            )..createSync(recursive: true);
            when(
              () => artifactBuilder.buildIpa(
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                codesign: any(named: 'codesign'),
                args: any(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: any(named: 'base64PublicKey'),
              ),
            ).thenAnswer(
              (_) async => IpaBuildResult(kernelFile: kernelFile),
            );
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
            when(
              () => artifactBuilder.buildElfAotSnapshot(
                appDillPath: any(named: 'appDillPath'),
                outFilePath: any(named: 'outFilePath'),
                additionalArgs: any(named: 'additionalArgs'),
              ),
            ).thenAnswer(
              (invocation) async =>
                  File(invocation.namedArguments[#outFilePath] as String)
                    ..createSync(recursive: true),
            );
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
                () => argResults[CommonArguments.splitDebugInfoArg.name],
              ).thenReturn(splitDebugInfoPath);
            });

            test('forwards --split-debug-info to builder', () async {
              try {
                await runWithOverrides(patcher.buildPatchArtifact);
              } catch (_) {}
              verify(
                () => artifactBuilder.buildElfAotSnapshot(
                  appDillPath: any(named: 'appDillPath'),
                  outFilePath: any(named: 'outFilePath'),
                  additionalArgs: [
                    '--dwarf-stack-traces',
                    '--resolve-dwarf-paths',
                    '--save-debugging-info=${splitDebugInfoFile.path}',
                  ],
                ),
              ).called(1);
            });
          });

          group('when releaseVersion is provided', () {
            test('forwards --build-name and --build-number to builder',
                () async {
              await runWithOverrides(
                () => patcher.buildPatchArtifact(releaseVersion: '1.2.3+4'),
              );
              verify(
                () => artifactBuilder.buildIpa(
                  flavor: any(named: 'flavor'),
                  exportOptionsPlist: any(named: 'exportOptionsPlist'),
                  codesign: any(named: 'codesign'),
                  target: any(named: 'target'),
                  args: any(
                    named: 'args',
                    that: containsAll(
                      ['--build-name=1.2.3', '--build-number=4'],
                    ),
                  ),
                ),
              ).called(1);
            });
          });

          group('when platform was specified via arg results rest', () {
            setUp(() {
              when(() => argResults.rest).thenReturn(['ios', '--verbose']);
            });

            test('returns xcarchive zip', () async {
              final artifact = await runWithOverrides(
                patcher.buildPatchArtifact,
              );
              expect(p.basename(artifact.path), endsWith('.zip'));
              verify(
                () => artifactBuilder.buildIpa(
                  exportOptionsPlist: any(named: 'exportOptionsPlist'),
                  codesign: any(named: 'codesign'),
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

            test('calls the buildIpa passing the key', () async {
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
                () => artifactBuilder.buildIpa(
                  exportOptionsPlist: any(named: 'exportOptionsPlist'),
                  codesign: any(named: 'codesign'),
                  args: any(named: 'args'),
                  flavor: any(named: 'flavor'),
                  target: any(named: 'target'),
                  base64PublicKey: 'public_key_encoded',
                ),
              ).called(1);
            });
          });

          test('returns xcarchive zip', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);
            expect(p.basename(artifact.path), endsWith('.zip'));
          });

          test('copies app.dill to build directory', () async {
            final copiedKernelFile = File(
              p.join(
                projectRoot.path,
                'build',
                'app.dill',
              ),
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
          platform: ReleasePlatform.ios,
          hash: '#',
          size: 42,
          url: 'https://example.com',
          podfileLockHash: 'podfile-lock-hash',
          canSideload: true,
        );
        late File releaseArtifactFile;

        void setUpProjectRootArtifacts() {
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
          releaseArtifactFile = File(
            p.join(
              Directory.systemTemp.createTempSync().path,
              'release.xcarchive',
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

        group('when patch .xcarchive does not exist', () {
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
                  releaseArtifact: releaseArtifactFile,
                ),
              ),
              exitsWithCode(ExitCode.software),
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
                additionalArgs: any(named: 'additionalArgs'),
              ),
            ).thenAnswer((_) async => linkPercentage);
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
            when(
              () => shorebirdEnv.flutterRevision,
            ).thenReturn(postLinkerFlutterRevision);
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
                      releaseArtifact: releaseArtifactFile,
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
                } catch (_) {}
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
                    dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
                    additionalArgs: any(named: 'additionalArgs'),
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

              group('when isLinkDebugInfoSupported is true', () {
                setUp(() {
                  when(
                    aotTools.isLinkDebugInfoSupported,
                  ).thenAnswer((_) async => true);
                });

                test('dumps debug info', () async {
                  await runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                      releaseArtifact: releaseArtifactFile,
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
                      dumpDebugInfoPath: any(
                        named: 'dumpDebugInfoPath',
                        that: isNotNull,
                      ),
                    ),
                  ).called(1);
                  verify(
                    () => logger.detail(
                      any(
                        that: contains(
                          'Link debug info saved to',
                        ),
                      ),
                    ),
                  ).called(1);
                });

                group('when aot_tools link fails', () {
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
                        dumpDebugInfoPath: any(
                          named: 'dumpDebugInfoPath',
                          that: isNotNull,
                        ),
                      ),
                    ).thenThrow(Exception('oops'));
                  });

                  test('dumps debug info and logs', () async {
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
                      () => logger.detail(
                        any(
                          that: contains(
                            'Link debug info saved to',
                          ),
                        ),
                      ),
                    ).called(1);
                  });
                });
              });

              group('when isLinkDebugInfoSupported is false', () {
                setUp(() {
                  when(aotTools.isLinkDebugInfoSupported)
                      .thenAnswer((_) async => false);
                });

                test('does not pass dumpDebugInfoPath to aotTools.link',
                    () async {
                  await runWithOverrides(
                    () => patcher.createPatchArtifacts(
                      appId: appId,
                      releaseId: releaseId,
                      releaseArtifact: releaseArtifactFile,
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
                      // ignore: avoid_redundant_argument_values
                      dumpDebugInfoPath: null,
                    ),
                  ).called(1);
                });
              });

              group('when code signing the patch', () {
                setUp(() {
                  final privateKey = File(
                    p.join(
                      Directory.systemTemp.createTempSync().path,
                      'test-private.pem',
                    ),
                  )..createSync();

                  when(() => argResults[CommonArguments.privateKeyArg.name])
                      .thenReturn(privateKey.path);

                  when(
                    () => codeSigner.sign(
                      message: any(named: 'message'),
                      privateKeyPemFile: any(named: 'privateKeyPemFile'),
                    ),
                  ).thenAnswer((invocation) {
                    final message =
                        invocation.namedArguments[#message] as String;
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
                    equals(
                      expectedSignature,
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
              hasAssetChanges: false,
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
                  hasAssetChanges: false,
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
              runWithOverrides(
                () => patcher.updatedCreatePatchMetadata(metadata),
              ),
              completion(
                const CreatePatchMetadata(
                  releasePlatform: ReleasePlatform.ios,
                  usedIgnoreAssetChangesFlag: allowAssetDiffs,
                  hasAssetChanges: true,
                  usedIgnoreNativeChangesFlag: allowNativeDiffs,
                  hasNativeChanges: false,
                  linkPercentage: linkPercentage,
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
      });
    },
    testOn: 'mac-os',
  );
}
