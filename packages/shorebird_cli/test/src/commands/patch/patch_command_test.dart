import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(PatchCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const arch = 'aarch64';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersion = '3.22.0';
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
    const diffStatus = DiffStatus(
      hasAssetChanges: false,
      hasNativeChanges: false,
    );
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
      flutterVersion: flutterVersion,
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
      podfileLockHash: null,
      canSideload: true,
    );
    const aabArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.aab',
      podfileLockHash: null,
      canSideload: true,
    );
    const supplementArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 422,
      url: 'https://example.com/supplement.zip',
      podfileLockHash: null,
      canSideload: false,
    );

    late AotTools aotTools;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late Patcher patcher;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;

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
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(CreatePatchMetadata.forTest());
      registerFallbackValue(DeploymentTrack.stable);
      registerFallbackValue(FakeDiffStatus());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(release);
      registerFallbackValue(FakeReleaseArtifact());
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      aotTools = MockAotTools();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      patcher = MockPatcher();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['platforms']).thenReturn(['android']);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(
        () => argResults['track'],
      ).thenReturn(DeploymentTrack.stable.channel);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(() => argResults.wasParsed('staging')).thenReturn(false);
      when(
        () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
      ).thenReturn(false);
      when(
        () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
      ).thenReturn(false);

      when(aotTools.isLinkDebugInfoSupported).thenAnswer((_) async => true);

      when(
        () => artifactManager.downloadWithProgressUpdates(
          any(),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async => File(''));

      when(() => cache.updateAll()).thenAnswer((_) async => {});

      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [release]);
      when(
        () => patcher.uploadPatchArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          track: any(named: 'track'),
          artifacts: any(named: 'artifacts'),
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
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: 'supplement',
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => supplementArtifact);

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(release);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(() => patcher.assertArgsAreValid()).thenAnswer((_) async {});
      when(() => patcher.assertPreconditions()).thenAnswer((_) async {});
      when(
        () => patcher.extractReleaseVersionFromArtifact(any()),
      ).thenAnswer((_) async => releaseVersion);
      when(
        () => patcher.buildPatchArtifact(
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => File(''));
      when(() => patcher.releaseType).thenReturn(ReleaseType.android);
      when(() => patcher.primaryReleaseArtifactArch).thenReturn('aab');
      when(
        () => patcher.createPatchArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          releaseArtifact: any(named: 'releaseArtifact'),
          supplementArtifact: any(named: 'supplementArtifact'),
        ),
      ).thenAnswer((_) async => patchArtifactBundles);
      when(
        () => patcher.updatedCreatePatchMetadata(any()),
      ).thenAnswer((_) async => patchMetadata);
      when(
        () => patcher.assertUnpatchableDiffs(
          releaseArtifact: any(named: 'releaseArtifact'),
          releaseArchive: any(named: 'releaseArchive'),
          patchArchive: any(named: 'patchArchive'),
        ),
      ).thenAnswer((_) async => diffStatus);

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

      when(
        () => shorebirdValidator.validateFlavors(
          flavorArg: any(named: 'flavorArg'),
        ),
      ).thenAnswer((_) async => {});

      command = PatchCommand(resolvePatcher: (_) => patcher)
        ..testArgResults = argResults;
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    group('run', () {
      group('when --staging is passed', () {
        setUp(() {
          when(() => argResults.wasParsed('staging')).thenReturn(true);
        });

        test(
            '''warns that staging flag will be deprecated and exits with usage code''',
            () async {
          await expectLater(
            runWithOverrides(command.run),
            completion(equals(ExitCode.usage.code)),
          );
          verify(
            () => logger.err(
              '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
            ),
          ).called(1);
        });
      });
    });

    group('createPatch', () {
      test('publishes the patch', () async {
        await runWithOverrides(() => command.createPatch(patcher));

        verify(
          () => patcher.uploadPatchArtifacts(
            appId: appId,
            releaseId: any(named: 'releaseId'),
            metadata: any(named: 'metadata'),
            track: any(named: 'track'),
            artifacts: patchArtifactBundles,
          ),
        ).called(1);
      });

      group('flavor validation', () {
        group('when no flavors are present', () {
          test('validates successfully', () async {
            await runWithOverrides(() => command.createPatch(patcher));

            verify(
              () => shorebirdValidator.validateFlavors(flavorArg: null),
            ).called(1);
          });
        });

        group('when flavors are present', () {
          const flavor = 'development';
          setUp(() {
            when(() => argResults['flavor']).thenReturn(flavor);
          });

          test('validates successfully', () async {
            await runWithOverrides(() => command.createPatch(patcher));

            verify(
              () => shorebirdValidator.validateFlavors(flavorArg: flavor),
            ).called(1);
          });
        });
      });

      group('correctly validates key pair', () {
        group('when no key pair is provided', () {
          test('is valid', () async {
            await expectLater(
              runWithOverrides(() => command.createPatch(patcher)),
              completes,
            );
          });
        });

        group(
          'when given existing private and public key files',
          () {
            test('is valid', () async {
              when(
                () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
              ).thenReturn(true);
              when(
                () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
              ).thenReturn(true);
              when(() => argResults[CommonArguments.privateKeyArg.name])
                  .thenReturn(createTempFile('private.pem').path);
              when(() => argResults[CommonArguments.publicKeyArg.name])
                  .thenReturn(createTempFile('public.pem').path);

              await expectLater(
                runWithOverrides(() => command.createPatch(patcher)),
                completes,
              );
            });
          },
        );

        group(
          'when given an existing private key and nonexistent public key',
          () {
            test('logs error and exits with usage code', () async {
              when(
                () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
              ).thenReturn(true);
              when(
                () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
              ).thenReturn(false);
              when(
                () => argResults[CommonArguments.privateKeyArg.name],
              ).thenReturn(createTempFile('private.pem').path);

              await expectLater(
                runWithOverrides(() => command.createPatch(patcher)),
                exitsWithCode(ExitCode.usage),
              );
              verify(
                () => logger.err(
                  'Both public and private keys must be provided.',
                ),
              ).called(1);
            });
          },
        );

        group('when given an existing public key and nonexistent private key',
            () {
          test('fails and logs the err', () async {
            when(
              () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
            ).thenReturn(false);
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
            ).thenReturn(true);
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(createTempFile('public.pem').path);

            await expectLater(
              runWithOverrides(() => command.createPatch(patcher)),
              exitsWithCode(ExitCode.usage),
            );
            verify(
              () => logger.err(
                'Both public and private keys must be provided.',
              ),
            ).called(1);
          });
        });

        group('when a supplemental release artifact exists', () {
          setUp(() {
            when(
              () => patcher.supplementaryReleaseArtifactArch,
            ).thenReturn('supplement');
          });

          test('downloads the supplemental release artifact', () async {
            await runWithOverrides(() => command.createPatch(patcher));

            verify(
              () => codePushClientWrapper.getReleaseArtifact(
                appId: appId,
                releaseId: release.id,
                arch: 'supplement',
                platform: releasePlatform,
              ),
            ).called(1);
            verify(
              () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                releaseArtifact: any(named: 'releaseArtifact'),
                supplementArtifact: any(named: 'supplementArtifact'),
              ),
            ).called(1);
          });

          group('when the artifact is not found', () {
            setUp(() {
              when(
                () => codePushClientWrapper.getReleaseArtifact(
                  appId: appId,
                  releaseId: release.id,
                  arch: 'supplement',
                  platform: releasePlatform,
                ),
              ).thenThrow(CodePushNotFoundException(message: 'Not found'));
            });

            test('gracefully continues to create patch', () async {
              await runWithOverrides(() => command.createPatch(patcher));
              verify(
                () => patcher.createPatchArtifacts(
                  appId: appId,
                  releaseId: release.id,
                  releaseArtifact: any(named: 'releaseArtifact'),
                  supplementArtifact: any(named: 'supplementArtifact'),
                ),
              ).called(1);
            });
          });
        });
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
            '🟢 Track: ${lightCyan.wrap('Stable')}',
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
          when(
            () => argResults['track'],
          ).thenReturn(DeploymentTrack.staging.channel);
        });

        test('isStaging returns true', () {
          expect(command.isStaging, isTrue);
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

      group('when is beta', () {
        setUp(() {
          when(
            () => argResults['track'],
          ).thenReturn(DeploymentTrack.beta.channel);
        });

        test('logs correct summary', () async {
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.name)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '🔵 Track: ${lightCyan.wrap('Beta')}',
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
            '🟢 Track: ${lightCyan.wrap('Stable')}',
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
          () => shorebirdValidator.validateFlavors(flavorArg: null),
          () => cache.updateAll(),
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
          () => patcher.buildPatchArtifact(releaseVersion: releaseVersion),
          () => patcher.assertUnpatchableDiffs(
                releaseArtifact: any(named: 'releaseArtifact'),
                releaseArchive: any(named: 'releaseArchive'),
                patchArchive: any(named: 'patchArchive'),
              ),
          () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => logger.confirm('Would you like to continue?'),
          () => patcher.updatedCreatePatchMetadata(any()),
          () => patcher.uploadPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                metadata: patchMetadata.toJson(),
                artifacts: any(named: 'artifacts'),
                track: DeploymentTrack.stable,
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
          () => shorebirdValidator.validateFlavors(flavorArg: null),
          () => cache.updateAll(),
          () => codePushClientWrapper.getApp(appId: appId),
          () => codePushClientWrapper.getReleases(appId: appId),
          () => logger.chooseOne<Release>(
                'Which release would you like to patch?',
                choices: any(named: 'choices'),
                display: captureAny(named: 'display'),
              ),
          () => codePushClientWrapper.getReleaseArtifact(
                appId: appId,
                releaseId: release.id,
                arch: patcher.primaryReleaseArtifactArch,
                platform: releasePlatform,
              ),
          () => patcher.assertUnpatchableDiffs(
                releaseArtifact: any(named: 'releaseArtifact'),
                releaseArchive: any(named: 'releaseArchive'),
                patchArchive: any(named: 'patchArchive'),
              ),
          () => patcher.createPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                releaseArtifact: any(named: 'releaseArtifact'),
              ),
          () => logger.confirm('Would you like to continue?'),
          () => patcher.uploadPatchArtifacts(
                appId: appId,
                releaseId: release.id,
                metadata: any(named: 'metadata'),
                artifacts: any(named: 'artifacts'),
                track: DeploymentTrack.stable,
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

      group('when prompting for releases, but there is none', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => []);
        });

        test('warns and exits', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.usage),
          );

          verify(
            () => logger.warn(
              '''No releases found for app $appId. You need to make first a release before you can create a patch.''',
            ),
          ).called(1);
        });
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
                flutterVersion: flutterVersion,
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
              () => shorebirdFlutter.installRevision(
                    revision: releaseFlutterRevision,
                  ),
              () => shorebirdEnv.copyWith(
                    flutterRevisionOverride: releaseFlutterRevision,
                  ),
              () => patcher.buildPatchArtifact(releaseVersion: releaseVersion),
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
          () => patcher.uploadPatchArtifacts(
            appId: appId,
            releaseId: release.id,
            metadata: any(named: 'metadata'),
            artifacts: any(named: 'artifacts'),
            track: DeploymentTrack.stable,
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
            flutterVersion: flutterVersion,
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

    group('when the target release does not contain the provided platform', () {
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
            flutterVersion: flutterVersion,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
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
            '''No release exists for android in release version ${release.version}. Please run shorebird release android to create one.''',
          ),
        ).called(1);
      });
    });

    group('when primary release artifact fails to download', () {
      final error = Exception('Failed to download primary release artifact.');

      setUp(() {
        when(
          () => artifactManager.downloadWithProgressUpdates(
            any(),
            message: any(named: 'message'),
          ),
        ).thenThrow(error);
      });

      test('logs error and exits with code 70', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          exitsWithCode(ExitCode.software),
        );
      });
    });

    group('when unpatchable diffs exist', () {
      group('when user cancels', () {
        setUp(() {
          when(
            () => patcher.assertUnpatchableDiffs(
              releaseArtifact: any(named: 'releaseArtifact'),
              releaseArchive: any(named: 'releaseArchive'),
              patchArchive: any(named: 'patchArchive'),
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
            () => patcher.assertUnpatchableDiffs(
              releaseArtifact: any(named: 'releaseArtifact'),
              releaseArchive: any(named: 'releaseArchive'),
              patchArchive: any(named: 'patchArchive'),
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
        when(
          () => argResults['track'],
        ).thenReturn(DeploymentTrack.staging.channel);
      });

      test('publishes to the staging track', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));

        verify(
          () => patcher.uploadPatchArtifacts(
            appId: appId,
            releaseId: release.id,
            metadata: any(named: 'metadata'),
            artifacts: any(named: 'artifacts'),
            track: DeploymentTrack.staging,
          ),
        ).called(1);
      });
    });
  });
}
