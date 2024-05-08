import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch_new/patch_new.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
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

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group('PatchNewCommand', () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const arch = 'aarch64';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const releasePlatform = ReleasePlatform.android;
    const releaseVersion = '1.2.3+1';
    const shorebirdYaml = ShorebirdYaml(appId: appId);

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

    late ArchiveDiffer archiveDiffer;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late Logger logger;
    late PatchDiffChecker patchDiffChecker;
    late Patcher patcher;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    late PatchNewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
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
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(Uri.parse('https://example.com'));
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      archiveDiffer = MockAndroidArchiveDiffer();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockLogger();
      progress = MockProgress();
      patchDiffChecker = MockPatchDiffChecker();
      patcher = MockPatcher();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['platform']).thenReturn(['android']);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => argResults.wasParsed(any())).thenReturn(true);

      when(() => artifactManager.downloadFile(any()))
          .thenAnswer((_) async => File(''));

      when(() => codePushClientWrapper.getApp(appId: any(named: 'appId')))
          .thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
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
      when(() => patcher.extractReleaseVersionFromArtifact(any()))
          .thenAnswer((_) async => releaseVersion);
      when(() => patcher.buildPatchArtifact())
          .thenAnswer((_) async => File(''));
      when(() => patcher.releaseType).thenReturn(ReleaseType.android);
      when(() => patcher.primaryReleaseArtifactArch).thenReturn('aab');
      when(
        () => patcher.createPatchArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer(
        (_) async => {
          Arch.arm32: const PatchArtifactBundle(
            arch: 'arm32',
            hash: '#',
            size: 42,
            path: '',
          ),
        },
      );

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

      command = PatchNewCommand(resolvePatcher: (_) => patcher)
        ..testArgResults = argResults;
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    group('hidden', () {
      test('is true', () {
        expect(command.hidden, true);
      });
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
          () => command.getPatcher(ReleaseType.ios),
          throwsA(isA<UnimplementedError>()),
        );
        expect(
          () => command.getPatcher(ReleaseType.iosFramework),
          throwsA(isA<UnimplementedError>()),
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
          () => codePushClientWrapper.getApp(appId: appId),
          () => codePushClientWrapper.getRelease(
                appId: appId,
                releaseVersion: releaseVersion,
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
      });
    });

    group('when release version is not specified', () {
      setUp(() {
        when(() => argResults.wasParsed('release-version')).thenReturn(false);
      });

      test(
          'executes commands in order, builds app to determine release version',
          () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verifyInOrder([
          () => patcher.assertPreconditions(),
          () => patcher.assertArgsAreValid(),
          () => codePushClientWrapper.getApp(appId: appId),
          () => patcher.buildPatchArtifact(),
          () => patcher.extractReleaseVersionFromArtifact(any()),
          () => codePushClientWrapper.getRelease(
                appId: appId,
                releaseVersion: releaseVersion,
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
            () => patcher.buildPatchArtifact(),
            () => shorebirdEnv.copyWith(
                  flutterRevisionOverride: releaseFlutterRevision,
                ),
            () => patcher.buildPatchArtifact(),
          ]);
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

    group('when the target release is in a draft state', () {
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
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {releasePlatform: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        );
      });

      test('logs error and exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );

        verify(
          () => logger.err(
            '''
Release ${release.version} is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.''',
          ),
        ).called(1);
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
