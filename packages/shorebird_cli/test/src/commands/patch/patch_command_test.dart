import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(PatchCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const arch = 'aarch64';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const releasePlatform = ReleasePlatform.android;
    const releaseVersion = '1.2.3+1';
    const patchArtifactBundles = {
      Arch.arm32: PatchArtifactBundle(
        arch: 'arm32',
        hash: '#',
        size: 42,
        path: '',
      ),
    };
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final patchMetadata = CreatePatchMetadata.forTest();

    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {releasePlatform: ReleaseStatus.active},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const releaseArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com',
    );
    const aabArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.aab',
    );

    late AotTools aotTools;
    late ArchiveDiffer archiveDiffer;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late PatchDiffChecker patchDiffChecker;
    late Patcher patcher;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    late PatchCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(CreatePatchMetadata.forTest());
      registerFallbackValue(DeploymentTrack.production);
      registerFallbackValue(FakeDiffStatus());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(release);
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(Uri.parse('https://example.com'));
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      aotTools = MockAotTools();
      archiveDiffer = MockAndroidArchiveDiffer();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      patchDiffChecker = MockPatchDiffChecker();
      patcher = MockPatcher();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['platforms']).thenReturn(['android']);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => argResults.wasParsed(any())).thenReturn(true);

      when(aotTools.isLinkDebugInfoSupported).thenAnswer((_) async => true);

      when(
        () => artifactManager.downloadFile(any()),
      ).thenAnswer((_) async => File(''));

      when(() => cache.updateAll()).thenAnswer((_) async => {});

      when(() => codePushClientWrapper.getApp(appId: any(named: 'appId')))
          .thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(() => codePushClientWrapper.getReleases(appId: any(named: 'appId')))
          .thenAnswer((_) async => [release]);
      when(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async {});

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
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: 'aab',
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => aabArtifact);

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(release);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenAnswer(
        (_) async => DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        ),
      );

      when(() => patcher.archiveDiffer).thenReturn(archiveDiffer);
      when(() => patcher.assertArgsAreValid()).thenAnswer((_) async {});
      when(() => patcher.assertPreconditions()).thenAnswer((_) async {});
      when(
        () => patcher.extractReleaseVersionFromArtifact(any()),
      ).thenAnswer((_) async => releaseVersion);
      when(
        () => patcher.buildPatchArtifact(),
      ).thenAnswer((_) async => File(''));
      when(() => patcher.releaseType).thenReturn(ReleaseType.android);
      when(() => patcher.primaryReleaseArtifactArch).thenReturn('aab');
      when(
        () => patcher.createPatchArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          releaseArtifact: any(named: 'releaseArtifact'),
        ),
      ).thenAnswer((_) async => patchArtifactBundles);
      when(
        () => patcher.createPatchMetadata(any()),
      ).thenAnswer((_) async => patchMetadata);

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => shorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return shorebirdEnv;
      });
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});

      command = PatchCommand(resolvePatcher: (_) => patcher)
        ..testArgResults = argResults;
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    group('getPatcher', () {
      test('maps the correct platform to the patcher', () async {
        expect(
          command.getPatcher(ReleaseType.android),
          isA<AndroidPatcher>(),
        );
        expect(
          command.getPatcher(ReleaseType.aar),
          isA<AarPatcher>(),
        );
        expect(
          command.getPatcher(ReleaseType.ios),
          isA<IosPatcher>(),
        );
        expect(
          command.getPatcher(ReleaseType.iosFramework),
          isA<IosFrameworkPatcher>(),
        );
      });
    });

    group('confirmCreatePatch', () {
      group('when has flavors', () {
        const flavor = 'development';
        setUp(() {
          when(() => argResults['flavor']).thenReturn(flavor);
        });

        test('logs correct summary', () async {
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '🍧 Flavor: ${lightCyan.wrap(flavor)}',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.name)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '🟢 Track: ${lightCyan.wrap('Production')}',
          ];
          await expectLater(
            runWithOverrides(
              () => command.confirmCreatePatch(
                app: appMetadata,
                releaseVersion: releaseVersion,
                patcher: patcher,
                patchArtifactBundles: patchArtifactBundles,
              ),
            ),
            completes,
          );
          verify(
            () => logger.info(
              any(that: contains(expectedSummary.join('\n'))),
            ),
          ).called(1);
        });
      });

      group('when is staging', () {
        setUp(() {
          when(() => argResults['staging']).thenReturn(true);
        });

        test('logs correct summary', () async {
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.name)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '🟠 Track: ${lightCyan.wrap('Staging')}',
          ];
          await expectLater(
            runWithOverrides(
              () => command.confirmCreatePatch(
                app: appMetadata,
                releaseVersion: releaseVersion,
                patcher: patcher,
                patchArtifactBundles: patchArtifactBundles,
              ),
            ),
            completes,
          );
          verify(
            () => logger.info(
              any(that: contains(expectedSummary.join('\n'))),
            ),
          ).called(1);
        });
      });

      group('when has link percentage', () {
        const linkPercentage = 42.1337;
        final debugInfoFile = File('debug-info.txt');

        setUp(() {
          when(() => patcher.linkPercentage).thenReturn(linkPercentage);
          when(() => patcher.debugInfoFile).thenReturn(debugInfoFile);
        });

        test('logs correct summary', () async {
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.name)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '🟢 Track: ${lightCyan.wrap('Production')}',
            '''🔗 Running ${lightCyan.wrap('${patcher.linkPercentage!.toStringAsFixed(1)}%')} on CPU''',
            '''🔍 Debug Info: ${lightCyan.wrap(patcher.debugInfoFile.path)}''',
          ];
          await expectLater(
            runWithOverrides(
              () => command.confirmCreatePatch(
                app: appMetadata,
                releaseVersion: releaseVersion,
                patcher: patcher,
                patchArtifactBundles: patchArtifactBundles,
              ),
            ),
            completes,
          );
          verify(
            () => logger.info(
              any(that: contains(expectedSummary.join('\n'))),
            ),
          ).called(1);
        });
      });
    });

    group('when flutter install fails', () {
      final error = Exception('Failed to install Flutter revision.');

      setUp(() {
        when(
          () => shorebirdFlutter.installRevision(
            revision: any(named: 'revision'),
          ),
        ).thenThrow(error);
      });

      test('exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );
      });
    });

    group('when release version is specified', () {
      setUp(() {
        when(() => argResults['release-version']).thenReturn(releaseVersion);
      });

      test('executes commands in order, only builds app once', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verifyInOrder([
          () => patcher.assertPreconditions(),
          () => patcher.assertArgsAreValid(),
          () => cache.updateAll(),
          () => codePushClientWrapper.getApp(appId: appId),
          () => codePushClientWrapper.getRelease(
                appId: appId,
                releaseVersion: releaseVersion,
              ),
          () => codePushClientWrapper.ensureReleaseIsNotActive(
                release: any(named: 'release'),
                platform: releasePlatform,
              ),
          () => codePushClientWrapper.getReleaseArtifact(
                appId: appId,
                releaseId: release.id,
                arch: patcher.primaryReleaseArtifactArch,
                platform: releasePlatform,
              ),
          () => patcher.buildPatchArtifact(),
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                allowAssetChanges: false,
                allowNativeChanges: false,
                archiveDiffer: archiveDiffer,
                localArtifact: any(named: 'localArtifact'),
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => logger.confirm('Would you like to continue?'),
          () => patcher.createPatchMetadata(any()),
          () => codePushClientWrapper.publishPatch(
                appId: appId,
                releaseId: release.id,
                metadata: patchMetadata,
                platform: releasePlatform,
                patchArtifactBundles: any(named: 'patchArtifactBundles'),
                track: DeploymentTrack.production,
              ),
        ]);
      });
    });

    group('when release version is not specified', () {
      setUp(() {
        when(() => argResults.wasParsed('release-version')).thenReturn(false);
      });

      test('executes commands in order, prompts to determine release version',
          () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        final verificationResult = verifyInOrder([
          () => patcher.assertPreconditions(),
          () => patcher.assertArgsAreValid(),
          () => cache.updateAll(),
          () => codePushClientWrapper.getApp(appId: appId),
          () => codePushClientWrapper.getReleases(appId: appId),
          () => logger.chooseOne<Release>(
                'Which release would you like to patch?',
                choices: any(named: 'choices'),
                display: captureAny(named: 'display'),
              ),
          () => codePushClientWrapper.ensureReleaseIsNotActive(
                release: any(named: 'release'),
                platform: releasePlatform,
              ),
          () => codePushClientWrapper.getReleaseArtifact(
                appId: appId,
                releaseId: release.id,
                arch: patcher.primaryReleaseArtifactArch,
                platform: releasePlatform,
              ),
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                allowAssetChanges: false,
                allowNativeChanges: false,
                archiveDiffer: archiveDiffer,
                localArtifact: any(named: 'localArtifact'),
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => logger.confirm('Would you like to continue?'),
          () => codePushClientWrapper.publishPatch(
                appId: appId,
                releaseId: release.id,
                metadata: any(named: 'metadata'),
                platform: releasePlatform,
                patchArtifactBundles: any(named: 'patchArtifactBundles'),
                track: DeploymentTrack.production,
              ),
        ]);

        // Verify that the logger.chooseOne<Release> display function is correct
        final displayFunctionCapture = verificationResult.captured.flattened
            .whereType<String Function(Release)>()
            .first;
        expect(
          displayFunctionCapture(release),
          equals(release.version),
        );
      });

      group('when running on CI', () {
        setUp(() {
          when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
        });

        group('when release Flutter version is not default', () {
          const releaseFlutterRevision = 'different-revision';

          setUp(() {
            when(
              () => codePushClientWrapper.getRelease(
                appId: any(named: 'appId'),
                releaseVersion: any(named: 'releaseVersion'),
              ),
            ).thenAnswer(
              (_) async => Release(
                id: 0,
                appId: appId,
                version: releaseVersion,
                flutterRevision: releaseFlutterRevision,
                displayName: '1.2.3+1',
                platformStatuses: {releasePlatform: ReleaseStatus.active},
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
            );
          });

          test('builds app twice if release flutter version is not default',
              () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.success.code));

            verifyInOrder([
              () => logger.info(
                    '''Tip: make your patches build faster by specifying --release-version''',
                  ),
              () => patcher.buildPatchArtifact(),
              () => patcher.extractReleaseVersionFromArtifact(any()),
              () => codePushClientWrapper.ensureReleaseIsNotActive(
                    release: any(named: 'release'),
                    platform: releasePlatform,
                  ),
              () => shorebirdFlutter.installRevision(
                    revision: releaseFlutterRevision,
                  ),
              () => shorebirdEnv.copyWith(
                    flutterRevisionOverride: releaseFlutterRevision,
                  ),
              () => patcher.buildPatchArtifact(),
            ]);
          });

          test('updates cache with both default and release Flutter revisions',
              () async {
            await runWithOverrides(command.run);

            verifyInOrder([
              cache.updateAll,
              () => shorebirdEnv.copyWith(
                    flutterRevisionOverride: releaseFlutterRevision,
                  ),
              cache.updateAll,
            ]);
          });
        });
      });
    });

    group('when dry-run is specified', () {
      setUp(() {
        when(() => argResults['dry-run']).thenReturn(true);
      });

      test('does not publish patch', () async {
        await expectLater(
          runWithOverrides(command.run),
          exitsWithCode(ExitCode.success),
        );

        verify(() => logger.info('No issues detected.')).called(1);

        verifyNever(() => logger.confirm(any()));
        verifyNever(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: release.id,
            metadata: any(named: 'metadata'),
            platform: releasePlatform,
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
            track: DeploymentTrack.production,
          ),
        );
      });
    });

    group('when running on CI', () {
      test('does not prompt for confirmation', () async {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verifyNever(() => logger.confirm(any()));
      });
    });

    group('when user declines to continue', () {
      setUp(() {
        when(() => logger.confirm(any())).thenReturn(false);
      });

      test('exits with message and success code', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.success),
        );
        verify(() => logger.info('Aborting.')).called(1);
      });
    });

    group('when primary release artifact fails to download', () {
      final error = Exception('Failed to download primary release artifact.');

      setUp(() {
        when(() => artifactManager.downloadFile(any())).thenThrow(error);
      });

      test('logs error and exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );

        verify(
          () => progress.fail(
            'Exception: Failed to download primary release artifact.',
          ),
        ).called(1);
      });
    });

    group('when unpatchable diffs exist', () {
      group('when user cancels', () {
        setUp(() {
          when(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              allowAssetChanges: any(named: 'allowAssetChanges'),
              allowNativeChanges: any(named: 'allowNativeChanges'),
              archiveDiffer: archiveDiffer,
              localArtifact: any(named: 'localArtifact'),
              releaseArtifact: any(named: 'releaseArtifact'),
            ),
          ).thenThrow(UserCancelledException());
        });

        test('exits with code 0', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.success),
          );
        });
      });

      group('when UnpatchableChangeException is thrown', () {
        setUp(() {
          when(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              allowAssetChanges: any(named: 'allowAssetChanges'),
              allowNativeChanges: any(named: 'allowNativeChanges'),
              archiveDiffer: archiveDiffer,
              localArtifact: any(named: 'localArtifact'),
              releaseArtifact: any(named: 'releaseArtifact'),
            ),
          ).thenThrow(UnpatchableChangeException());
        });

        test('logs and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );

          verify(() => logger.info('Exiting.')).called(1);
        });
      });
    });

    group('when patching to the staging track', () {
      setUp(() {
        when(() => argResults['staging']).thenReturn(true);
      });

      test('publishes to the staging track', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verify(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: release.id,
            metadata: any(named: 'metadata'),
            platform: releasePlatform,
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
            track: DeploymentTrack.staging,
          ),
        ).called(1);
      });
    });
  });
}
