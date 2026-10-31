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
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
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
  useTempWorkingDirectory();
  group(IosPatcher, () {
    late AotTools aotTools;
    late Apple apple;
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late CodeSigner codeSigner;
    late Doctor doctor;
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
    late IosPatcher patcher;

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
      registerFallbackValue(FakeArgResults());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(const AppleArchiveDiffer());
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ShorebirdArtifact.genSnapshotIos);
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      aotTools = MockAotTools();
      apple = MockApple();
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      when(
        () => codeSigner.canonicalPublicKeyPem(any()),
      ).thenAnswer(
        (invocation) => invocation.positionalArguments.single as String,
      );
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

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(
        () => shorebirdEnv.buildDirectory,
      ).thenReturn(Directory(p.join(projectRoot.path, 'build')));
      when(() => shorebirdEnv.iosSupplementDirectory).thenReturn(
        Directory(p.join(projectRoot.path, 'build', 'shorebird', 'ios')),
      );
      when(() => shorebirdEnv.iosPodfileLockHash).thenReturn(null);

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

    group('supplementaryReleaseArtifactArch', () {
      test('is "ios_supplement"', () {
        expect(patcher.supplementaryReleaseArtifactArch, 'ios_supplement');
      });
    });

    group('releaseType', () {
      test('is ReleaseType.ios', () {
        expect(patcher.releaseType, ReleaseType.ios);
      });
    });

    group('minimumFlutterVersion', () {
      test('is minimumPatchableIosFlutterVersion', () {
        expect(
          patcher.minimumFlutterVersion,
          minimumPatchableIosFlutterVersion,
        );
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
              supportedOperatingSystems: {NativePlatform.macOS},
            ),
          ).called(1);
        });
      });
    });

    group('assertArgsAreValid', () {
      test('returns normally when --export-options-plist is absent', () async {
        await expectLater(
          runWithOverrides(patcher.assertArgsAreValid),
          completes,
        );
      });

      group('when --export-options-plist is provided', () {
        late Directory tempDir;

        setUp(() {
          tempDir = Directory.systemTemp.createTempSync(
            'export_options_patcher_',
          );
        });

        tearDown(() {
          tempDir.deleteSync(recursive: true);
        });

        File writePlist(String body) {
          return File(p.join(tempDir.path, 'ExportOptions.plist'))
            ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
''');
        }

        test(
          '''logs error and exits with usage when manageAppVersionAndBuildNumber is true''',
          () async {
            final file = writePlist(
              '<key>manageAppVersionAndBuildNumber</key><true/>',
            );
            when(
              () => argResults[CommonArguments.exportOptionsPlistArg.name],
            ).thenReturn(file.path);

            await expectLater(
              () => runWithOverrides(patcher.assertArgsAreValid),
              exitsWithCode(ExitCode.usage),
            );
            verify(
              () => logger.err(
                any(that: contains('manageAppVersionAndBuildNumber')),
              ),
            ).called(1);
          },
        );
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
          verifyNever(() => logger.warn(any()));
        });
      });

      group('when native changes are detected', () {
        const nativeChangeDiffStatus = DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: true,
        );

        const podfileLockHash = 'podfile-lock-hash';

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

          when(
            () => shorebirdEnv.iosPodfileLockHash,
          ).thenReturn(podfileLockHash);
        });

        group('when release has podspec lock hash', () {
          group('when release podspec lock hash matches patch', () {
            const releaseArtifact = ReleaseArtifact(
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

            setUp(() {
              when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
              when(
                () => logger.confirm(any(), hint: any(named: 'hint')),
              ).thenReturn(true);
            });

            test('does not warn of native changes', () async {
              final diffStatus = await runWithOverrides(
                () => patcher.assertUnpatchableDiffs(
                  releaseArtifact: releaseArtifact,
                  releaseArchive: File(''),
                  patchArchive: File(''),
                ),
              );
              expect(diffStatus, equals(nativeChangeDiffStatus));
              verifyNever(() => logger.warn(any()));
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
              podfileLockHash: 'non-matching podfile-lock-hash',
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
                  verifyNever(
                    () => logger.confirm(any(), hint: any(named: 'hint')),
                  );
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
                    when(
                      () => logger.confirm(any(), hint: any(named: 'hint')),
                    ).thenReturn(true);
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
                    when(
                      () => logger.confirm(any(), hint: any(named: 'hint')),
                    ).thenReturn(false);
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
                      throwsA(
                        isA<UnpatchableChangeException>().having(
                          (e) => e.changes,
                          'changes',
                          {UnpatchableChange.native},
                        ),
                      ),
                    );
                    verify(
                      () => logger.err(
                        any(
                          that: startsWith(
                            'Your ios/Podfile.lock is different',
                          ),
                        ),
                      ),
                    ).called(1);
                    verifyNever(() => logger.warn(any()));
                  });
                },
              );
            });
          });
        });

        group('when release has no podspec lock hash', () {
          // Releases made before Podfile.lock hashes were recorded have
          // nothing to compare against, so the native diff passes through
          // without a warning or prompt.
          const releaseArtifact = ReleaseArtifact(
            id: 0,
            releaseId: 0,
            arch: 'aarch64',
            platform: ReleasePlatform.ios,
            hash: '#',
            size: 42,
            url: 'https://example.com',
            canSideload: true,
          );

          setUp(() {
            when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
            when(
              () => logger.confirm(any(), hint: any(named: 'hint')),
            ).thenReturn(true);
          });

          test(
            'returns diff status without warning or prompting',
            () async {
              final diffStatus = await runWithOverrides(
                () => patcher.assertUnpatchableDiffs(
                  releaseArtifact: releaseArtifact,
                  releaseArchive: File(''),
                  patchArchive: File(''),
                ),
              );
              expect(diffStatus, equals(nativeChangeDiffStatus));
              verifyNever(() => logger.warn(any()));
              verifyNever(
                () => logger.confirm(any(), hint: any(named: 'hint')),
              );
            },
          );
        });
      });
    });

    group('buildPatchArtifact', () {
      group('when build fails with ProcessException', () {
        const exception = ProcessException('flutter', [
          'build',
          'ipa',
        ], 'Build failed');

        setUp(() {
          when(
            () => artifactBuilder.buildIpa(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
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

      group('when build fails with ArtifactBuildException', () {
        final exception = ArtifactBuildException('Build failed');
        setUp(() {
          when(
            () => artifactBuilder.buildIpa(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
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

      group('when elf aot snapshot build fails', () {
        const exception = FileSystemException('error');
        setUp(() {
          when(
            () => artifactBuilder.buildIpa(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer(
            (_) async =>
                AppleBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => artifactBuilder.buildElfAotSnapshot(
              appDillPath: any(named: 'appDillPath'),
              outFilePath: any(named: 'outFilePath'),
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
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
            () => artifactBuilder.buildIpa(
              codesign: any(named: 'codesign'),
              args: any(named: 'args'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              base64PublicKey: any(named: 'base64PublicKey'),
              ddMaxBytes: any(named: 'ddMaxBytes'),
            ),
          ).thenAnswer((_) async => AppleBuildResult(kernelFile: kernelFile));
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
              genSnapshotArtifact: any(named: 'genSnapshotArtifact'),
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
              () =>
                  argResults.wasParsed(CommonArguments.splitDebugInfoArg.name),
            ).thenReturn(true);
            when(
              () => argResults[CommonArguments.splitDebugInfoArg.name],
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

        group('when releaseVersion is provided', () {
          test('forwards --build-name and --build-number to builder', () async {
            await runWithOverrides(
              () => patcher.buildPatchArtifact(releaseVersion: '1.2.3+4'),
            );
            verify(
              () => artifactBuilder.buildIpa(
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

        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['ios', '--verbose']);
          });

          test('returns xcarchive zip', () async {
            final artifact = await runWithOverrides(patcher.buildPatchArtifact);
            expect(p.basename(artifact.path), endsWith('.zip'));
            verify(
              () => artifactBuilder.buildIpa(
                codesign: any(named: 'codesign'),
                args: ['--verbose'],
              ),
            ).called(1);
          });
        });

        group('when the key pair is provided', () {
          setUp(() {
            when(
              () => codeSigner.base64PublicKeyFromPem(any()),
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
                codesign: any(named: 'codesign'),
                args: any(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: 'public_key_encoded',
              ),
            ).called(1);
          });

          test('passes a key from --public-key-cmd to buildIpa', () async {
            when(
              () => argResults[CommonArguments.publicKeyCmd.name],
            ).thenReturn('print-key');
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyCmd.name),
            ).thenReturn(true);
            when(
              () => codeSigner.runPublicKeyCmd('print-key'),
            ).thenAnswer((_) async => 'pem-from-cmd');
            await runWithOverrides(patcher.buildPatchArtifact);

            verify(
              () => codeSigner.base64PublicKeyFromPem('pem-from-cmd'),
            ).called(1);

            verify(
              () => artifactBuilder.buildIpa(
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
            p.join(projectRoot.path, 'build', 'app.dill'),
          );
          expect(copiedKernelFile.existsSync(), isFalse);
          await runWithOverrides(patcher.buildPatchArtifact);
          expect(copiedKernelFile.existsSync(), isTrue);
        });

        group('when extraBuildArgs has obfuscation flags', () {
          late File obfuscationMapFile;

          setUp(() {
            obfuscationMapFile =
                File(
                    p.join(
                      Directory.systemTemp.createTempSync().path,
                      'obfuscation_map.json',
                    ),
                  )
                  ..createSync(recursive: true)
                  ..writeAsStringSync('{"key": "value"}');
          });

          test('includes obfuscation flags in build args', () async {
            final loadMapOption =
                '--load-obfuscation-map=${obfuscationMapFile.path}';
            patcher
              ..obfuscate = true
              ..obfuscationMapPath = obfuscationMapFile.path
              ..extraBuildArgs = [
                '--obfuscate',
                '--extra-gen-snapshot-options=$loadMapOption',
                '--split-debug-info=build/shorebird/symbols',
              ];
            await runWithOverrides(patcher.buildPatchArtifact);

            final captured = verify(
              () => artifactBuilder.buildIpa(
                codesign: any(named: 'codesign'),
                args: captureAny(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: any(named: 'base64PublicKey'),
                ddMaxBytes: any(named: 'ddMaxBytes'),
              ),
            ).captured;

            final args = captured.last as List<String>;
            expect(args, contains('--obfuscate'));
            expect(
              args.any((a) => a.startsWith('--split-debug-info=')),
              isTrue,
            );
            expect(
              args,
              contains(
                '--extra-gen-snapshot-options='
                '--load-obfuscation-map=${obfuscationMapFile.path}',
              ),
            );
          });
        });

        group('when extraBuildArgs is empty', () {
          test('does not inject obfuscation flags', () async {
            await runWithOverrides(patcher.buildPatchArtifact);

            final captured = verify(
              () => artifactBuilder.buildIpa(
                codesign: any(named: 'codesign'),
                args: captureAny(named: 'args'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                base64PublicKey: any(named: 'base64PublicKey'),
                ddMaxBytes: any(named: 'ddMaxBytes'),
              ),
            ).captured;

            final args = captured.last as List<String>;
            expect(args, isNot(contains('--obfuscate')));
            expect(
              args.any(
                (a) => a.startsWith(
                  '--extra-gen-snapshot-options=--load-obfuscation-map',
                ),
              ),
              isFalse,
            );
          });
        });
      });
    });

    group('createPatchArtifacts', () {
      const postLinkerFlutterRevision = // cspell: disable-next-line
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
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
      late Directory supplementDirectory;

      void setUpProjectRootArtifacts() {
        File(
          p.join(projectRoot.path, 'build', elfAotSnapshotFileName),
        ).createSync(recursive: true);
        Directory(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'framework',
            'Release',
            'App.xcframework',
          ),
        ).createSync(recursive: true);
        File(
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
            'Frameworks',
            'App.framework',
            'App',
          ),
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
        supplementDirectory = Directory.systemTemp.createTempSync();

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
          when(() => artifactManager.getXcarchiveDirectory()).thenReturn(null);
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

      group('when linking', () {
        late Directory appDirectory;

        setUp(() {
          appDirectory = Directory(
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
          );
          when(
            () => artifactManager.getIosAppDirectory(
              xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
            ),
          ).thenReturn(appDirectory);
          when(
            () => shorebirdEnv.flutterRevision,
          ).thenReturn(postLinkerFlutterRevision);
          when(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              aotOutputFile: any(named: 'aotOutputFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              vmCodeFile: any(named: 'vmCodeFile'),
              ddMaxBytes: any(named: 'ddMaxBytes'),
            ),
          ).thenAnswer(
            (_) async => const LinkResult.success(linkPercentage: 100),
          );
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotIos,
            ),
          ).thenReturn('path/to/analyze_snapshot');
          when(
            aotTools.isGeneratePatchDiffBaseSupported,
          ).thenAnswer((_) async => true);
          when(
            () => aotTools.generatePatchDiffBase(
              analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
              releaseSnapshot: any(named: 'releaseSnapshot'),
              outputDirectory: any(named: 'outputDirectory'),
            ),
          ).thenAnswer((invocation) async {
            final outputDirectory =
                invocation.namedArguments[#outputDirectory] as Directory;
            return File(p.join(outputDirectory.path, 'diff_base'))
              ..createSync();
          });
          when(
            () => artifactManager.createDiff(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
            ),
          ).thenAnswer((_) async => 'path/to/diff');
          setUpProjectRootArtifacts();
        });

        // The link, diff and bundle steps themselves are tested once in
        // apple_patcher_mixin_test.dart; these cover the iOS wiring.
        test(
          'links against the App binary in the release .app, using the '
          'release supplement',
          () async {
            await runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifactFile,
                supplementDirectory: supplementDirectory,
              ),
            );

            verify(
              () => apple.runLinker(
                kernelFile: any(named: 'kernelFile'),
                aotOutputFile: any(named: 'aotOutputFile'),
                releaseArtifact: any(
                  named: 'releaseArtifact',
                  that: isA<File>().having(
                    (f) => f.path,
                    'path',
                    p.join(
                      appDirectory.path,
                      'Frameworks',
                      'App.framework',
                      'App',
                    ),
                  ),
                ),
                splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
                vmCodeFile: any(named: 'vmCodeFile'),
                ddMaxBytes: any(named: 'ddMaxBytes'),
              ),
            ).called(1);
            verify(
              () => apple.copySupplementFilesToSnapshotDirs(
                releaseSupplementDir: supplementDirectory,
                releaseSnapshotDir: any(named: 'releaseSnapshotDir'),
                patchSupplementDir: any(named: 'patchSupplementDir'),
                patchSnapshotDir: any(named: 'patchSnapshotDir'),
              ),
            ).called(1);
          },
        );

        test('passes --dd-max-bytes to the linker', () async {
          when(
            () => argResults[CommonArguments.ddMaxBytesArg.name],
          ).thenReturn('8192');

          await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
            ),
          );

          verify(
            () => apple.runLinker(
              kernelFile: any(named: 'kernelFile'),
              aotOutputFile: any(named: 'aotOutputFile'),
              releaseArtifact: any(named: 'releaseArtifact'),
              splitDebugInfoArgs: any(named: 'splitDebugInfoArgs'),
              vmCodeFile: any(named: 'vmCodeFile'),
              ddMaxBytes: 8192,
            ),
          ).called(1);
        });

        test('bundles the local Podfile.lock hash', () async {
          when(
            () => shorebirdEnv.iosPodfileLockHash,
          ).thenReturn('podfile-lock-hash');

          final patchBundle = await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
            ),
          );

          expect(
            patchBundle[Arch.arm64]!.podfileLockHash,
            equals('podfile-lock-hash'),
          );
        });

        test('leaves no temporary files behind', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(
            systemTemp,
            () => runWithOverrides(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: releaseId,
                releaseArtifact: releaseArtifactFile,
              ),
            ),
          );

          expect(systemTemp.listSync(), isEmpty);
        });

        test('keeps a supplement directory it was given', () async {
          await runWithOverrides(
            () => patcher.createPatchArtifacts(
              appId: appId,
              releaseId: releaseId,
              releaseArtifact: releaseArtifactFile,
              supplementDirectory: supplementDirectory,
            ),
          );

          expect(supplementDirectory.existsSync(), isTrue);
        });

        group('when the release .app does not exist', () {
          setUp(() {
            when(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
              ),
            ).thenReturn(null);
          });

          test('exits with an error saying the .app is missing', () async {
            await expectLater(
              () => runWithOverrides(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: releaseId,
                  releaseArtifact: releaseArtifactFile,
                ),
              ),
              exitsWithError(
                message:
                    'The release .xcarchive downloaded from Shorebird has no '
                    'Products/Applications/*.app directory.',
                hint: allOf(
                  startsWith('Re-run to download it again.'),
                  endsWith('Run: shorebird release ios'),
                ),
                exitCode: ExitCode.software,
              ),
            );
          });
        });
      });
    });

    group('extractReleaseVersionFromArtifact', () {
      late File infoPlist;

      setUp(() {
        final xcarchiveDirectory = Directory(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'archive',
            'Runner.xcarchive',
          ),
        );
        infoPlist = File(p.join(xcarchiveDirectory.path, 'Info.plist'));
        when(
          () => artifactManager.getXcarchiveDirectory(),
        ).thenReturn(xcarchiveDirectory);
      });

      group('when xcarchive directory does not exist', () {
        setUp(() {
          when(() => artifactManager.getXcarchiveDirectory()).thenReturn(null);
        });

        test('exits with an error naming the expected archive path', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.extractReleaseVersionFromArtifact(File('')),
            ),
            exitsWithError(
              message:
                  'No .xcarchive found in '
                  '${p.join(projectRoot.path, 'build', 'ios', 'archive')}, '
                  'where `flutter build ipa` writes it.',
              hint: 'Re-run with --verbose to see the build output.',
              exitCode: ExitCode.software,
            ),
          );
        });
      });

      group('when Info.plist does not exist', () {
        test('exits with an error and the hint', () async {
          await expectLater(
            () => runWithOverrides(
              () => patcher.extractReleaseVersionFromArtifact(File('')),
            ),
            exitsWithError(
              message: 'No Info.plist file found at ${infoPlist.path}',
              hint: passReleaseVersionHint,
              exitCode: ExitCode.software,
            ),
          );
        });
      });

      group('when empty Info.plist does exist', () {
        setUp(() {
          infoPlist
            ..createSync(recursive: true)
            ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict></dict>
</plist>
''');
        });

        test('exits with an error and the hint', () async {
          await expectLater(
            runWithOverrides(
              () => patcher.extractReleaseVersionFromArtifact(File('')),
            ),
            exitsWithError(
              message: startsWith('Failed to determine release version'),
              hint: passReleaseVersionHint,
              exitCode: ExitCode.software,
            ),
          );
        });
      });

      group('when Info.plist does exist', () {
        setUp(() {
          infoPlist
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

      group('when linker is not enabled', () {
        test('returns correct metadata', () async {
          const metadata = CreatePatchMetadata(
            releasePlatform: ReleasePlatform.ios,
            usedIgnoreAssetChangesFlag: allowAssetDiffs,
            hasAssetChanges: false,
            usedIgnoreNativeChangesFlag: allowNativeDiffs,
            hasNativeChanges: true,
            inferredReleaseVersion: false,
            isSigned: false,
            environment: BuildEnvironmentMetadata(
              flutterRevision: flutterRevision,
              operatingSystem: operatingSystem,
              operatingSystemVersion: operatingSystemVersion,
              shorebirdVersion: packageVersion,
              shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
              usesShorebirdCodePushPackage: false,
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
                inferredReleaseVersion: false,
                isSigned: false,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                  usesShorebirdCodePushPackage: false,
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
            hasAssetChanges: true,
            usedIgnoreNativeChangesFlag: allowNativeDiffs,
            hasNativeChanges: false,
            inferredReleaseVersion: false,
            isSigned: true,
            environment: BuildEnvironmentMetadata(
              flutterRevision: flutterRevision,
              operatingSystem: operatingSystem,
              operatingSystemVersion: operatingSystemVersion,
              shorebirdVersion: packageVersion,
              shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
              usesShorebirdCodePushPackage: false,
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
                inferredReleaseVersion: false,
                linkPercentage: linkPercentage,
                linkMetadata: linkMetadata,
                isSigned: true,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  xcodeVersion: xcodeVersion,
                  usesShorebirdCodePushPackage: false,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                ),
              ),
            ),
          );
        });
      });
    });
  }, testOn: 'mac-os');
}
