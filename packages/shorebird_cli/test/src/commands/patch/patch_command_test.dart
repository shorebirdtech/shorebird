import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
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

class _FakeRelease extends Fake with EquatableMixin implements Release {
  _FakeRelease({required this.updatedAt});

  @override
  final DateTime updatedAt;

  @override
  List<Object?> get props => [updatedAt];
}

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
      platformStatuses: const {releasePlatform: ReleaseStatus.active},
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
        () => argResults[CommonArguments.minLinkPercentage.name],
      ).thenReturn(CommonArguments.minLinkPercentage.defaultValue);
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
        () => codePushClientWrapper.maybeGetReleaseArtifact(
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
      when(() => shorebirdEnv.usesShorebirdCodePushPackage).thenReturn(false);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () =>
            shorebirdFlutter.installRevision(revision: any(named: 'revision')),
      ).thenAnswer((_) async => {});

      when(
        () => shorebirdValidator.validateFlavors(
          flavorArg: any(named: 'flavorArg'),
          releasePlatform: any(named: 'releasePlatform'),
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
          },
        );
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
              () => shorebirdValidator.validateFlavors(
                flavorArg: null,
                releasePlatform: ReleasePlatform.android,
              ),
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
              () => shorebirdValidator.validateFlavors(
                flavorArg: flavor,
                releasePlatform: ReleasePlatform.android,
              ),
            ).called(1);
          });
        });

        group('when flavor validation fails', () {
          setUp(() {
            when(
              () => shorebirdValidator.validateFlavors(
                flavorArg: any(named: 'flavorArg'),
                releasePlatform: any(named: 'releasePlatform'),
              ),
            ).thenThrow(ValidationFailedException());
          });

          test('exits with code 78 (config)', () async {
            await expectLater(
              runWithOverrides(() => command.createPatch(patcher)),
              exitsWithCode(ExitCode.config),
            );
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

        group('when given existing private and public key files', () {
          test('is valid', () async {
            when(
              () => argResults.wasParsed(CommonArguments.privateKeyArg.name),
            ).thenReturn(true);
            when(
              () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
            ).thenReturn(true);
            when(
              () => argResults[CommonArguments.privateKeyArg.name],
            ).thenReturn(createTempFile('private.pem').path);
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(createTempFile('public.pem').path);

            await expectLater(
              runWithOverrides(() => command.createPatch(patcher)),
              completes,
            );
          });
        });

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

        group(
          'when given an existing public key and nonexistent private key',
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
          },
        );

        group('when a supplemental release artifact exists', () {
          setUp(() {
            when(
              () => patcher.supplementaryReleaseArtifactArch,
            ).thenReturn('supplement');
          });

          test('downloads the supplemental release artifact', () async {
            await runWithOverrides(() => command.createPatch(patcher));

            verify(
              () => codePushClientWrapper.maybeGetReleaseArtifact(
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
        expect(command.getPatcher(ReleaseType.aar), isA<AarPatcher>());
        expect(command.getPatcher(ReleaseType.android), isA<AndroidPatcher>());
        expect(command.getPatcher(ReleaseType.ios), isA<IosPatcher>());
        expect(
          command.getPatcher(ReleaseType.iosFramework),
          isA<IosFrameworkPatcher>(),
        );
        expect(command.getPatcher(ReleaseType.linux), isA<LinuxPatcher>());
        expect(command.getPatcher(ReleaseType.macos), isA<MacosPatcher>());
        expect(command.getPatcher(ReleaseType.windows), isA<WindowsPatcher>());
      });
    });

    group('confirmCreatePatch', () {
      group('when using a custom deployment track', () {
        setUp(() {
          when(() => argResults['track']).thenReturn('custom-track');
        });

        test('logs correct summary', () async {
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '⚪️ Track: ${lightCyan.wrap('custom-track')}',
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
            () => logger.info(any(that: contains(expectedSummary.join('\n')))),
          ).called(1);
        });
      });

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
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
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
            () => logger.info(any(that: contains(expectedSummary.join('\n')))),
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
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
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
            () => logger.info(any(that: contains(expectedSummary.join('\n')))),
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
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
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
            () => logger.info(any(that: contains(expectedSummary.join('\n')))),
          ).called(1);
        });
      });

      group('when has link percentage', () {
        const linkPercentage = 42.1337;
        late Directory buildDirectory;

        setUp(() {
          buildDirectory = Directory.systemTemp.createTempSync();
          when(() => shorebirdEnv.buildDirectory).thenReturn(buildDirectory);
          when(() => patcher.linkPercentage).thenReturn(linkPercentage);
        });

        test('logs correct summary', () async {
          final debugInfoFile = File(
            p.join(buildDirectory.path, 'patch-debug.zip'),
          );
          final expectedSummary = [
            '''📱 App: ${lightCyan.wrap(appDisplayName)} ${lightCyan.wrap('($appId)')}''',
            '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
            '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[arm32 (42 B)]')}''',
            '🟢 Track: ${lightCyan.wrap('Stable')}',
            '''🔍 Debug Info: ${lightCyan.wrap(debugInfoFile.path)}''',
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
            () => logger.info(any(that: contains(expectedSummary.join('\n')))),
          ).called(1);
        });

        group('when min-link-percentage is specified', () {
          group('when link percentage is higher than min', () {
            const minLinkPercentageArg = '40';

            setUp(() {
              when(
                () => argResults[CommonArguments.minLinkPercentage.name],
              ).thenReturn(minLinkPercentageArg);
            });

            test('completes, does not print error message', () async {
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

              verifyNever(() {
                logger.err(
                  any(that: contains('is below the minimum threshold')),
                );
              });
            });
          });

          group('when link percentage is lower than min', () {
            const minLinkPercentageArg = '50';

            setUp(() {
              when(
                () => argResults[CommonArguments.minLinkPercentage.name],
              ).thenReturn(minLinkPercentageArg);
            });

            test('prints error message and exits', () async {
              await expectLater(
                runWithOverrides(
                  () => command.confirmCreatePatch(
                    app: appMetadata,
                    releaseVersion: releaseVersion,
                    patcher: patcher,
                    patchArtifactBundles: patchArtifactBundles,
                  ),
                ),
                exitsWithCode(ExitCode.software),
              );

              verify(
                () => logger.err(
                  '''The link percentage of this patch ($linkPercentage%) is below the minimum threshold (50%). Exiting.''',
                ),
              ).called(1);
            });
          });
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
          () => shorebirdValidator.validateFlavors(
            flavorArg: null,
            releasePlatform: ReleasePlatform.android,
          ),
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
          () => patcher.updatedCreatePatchMetadata(
            any(
              that: isA<CreatePatchMetadata>().having(
                (m) => m.inferredReleaseVersion,
                'inferredReleaseVersion',
                isFalse,
              ),
            ),
          ),
          () => patcher.uploadPatchArtifacts(
            appId: appId,
            releaseId: release.id,
            metadata: patchMetadata.toJson(),
            artifacts: any(named: 'artifacts'),
            track: DeploymentTrack.stable,
          ),
        ]);
      });

      group('when building artifact throws ArtifactBuildException', () {
        late ArtifactBuildException exception;

        setUp(() {
          exception = MockArtifactBuildException();
          when(() => exception.message).thenReturn('oops');
          when(() => exception.fixRecommendation).thenReturn('fix it');
          when(
            () => patcher.buildPatchArtifact(
              releaseVersion: any(named: 'releaseVersion'),
            ),
          ).thenThrow(exception);
        });

        test('logs error, fixes, and throws ProcessExit', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(() => logger.err(exception.message)).called(1);
          verify(() => logger.info('fix it')).called(1);
        });
      });

      group('when building artifact throws generic Exception', () {
        late Exception exception;

        setUp(() {
          exception = Exception('oops');
          when(
            () => patcher.buildPatchArtifact(
              releaseVersion: any(named: 'releaseVersion'),
            ),
          ).thenThrow(exception);
        });

        test('logs error, and throws ProcessExit', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err('Failed to build patch artifacts: $exception'),
          ).called(1);
        });
      });
    });

    group('when release version is latest', () {
      setUp(() {
        when(() => argResults['release-version']).thenReturn('latest');
      });

      group('when no releases for the target platform exist', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer(
            (_) async => [
              Release(
                id: 0,
                appId: appId,
                version: releaseVersion,
                flutterRevision: flutterRevision,
                flutterVersion: flutterVersion,
                displayName: '1.0.0+1',
                platformStatuses: const {
                  ReleasePlatform.windows: ReleaseStatus.active,
                },
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
            ],
          );
        });

        test('warns and exits', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.usage),
          );

          verify(
            () => codePushClientWrapper.getReleases(appId: appId),
          ).called(1);
          verify(
            () => logger.warn(
              '''No ${releasePlatform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
            ),
          ).called(1);
        });
      });

      group('when multiple releases for the target platform exist', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer(
            (_) async => [
              Release(
                id: 0,
                appId: appId,
                version: releaseVersion,
                flutterRevision: flutterRevision,
                flutterVersion: flutterVersion,
                displayName: releaseVersion,
                platformStatuses: const {releasePlatform: ReleaseStatus.active},
                createdAt: DateTime(2024),
                updatedAt: DateTime(2024),
              ),
              Release(
                id: 1,
                appId: appId,
                version: '99.99.99+99',
                flutterRevision: flutterRevision,
                flutterVersion: flutterVersion,
                displayName: '99.99.99+99',
                platformStatuses: const {releasePlatform: ReleaseStatus.active},
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
            ],
          );
        });

        test('uses the latest version', () async {
          await expectLater(runWithOverrides(command.run), completes);
          verify(
            () => codePushClientWrapper.getReleases(appId: appId),
          ).called(1);
          verify(
            () => patcher.buildPatchArtifact(releaseVersion: releaseVersion),
          ).called(1);
        });
      });
    });

    group('when release version is not specified', () {
      setUp(() {
        when(() => argResults.wasParsed('release-version')).thenReturn(false);
      });

      test(
        'executes commands in order, prompts to determine release version',
        () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));

          final verificationResult = verifyInOrder([
            () => patcher.assertPreconditions(),
            () => patcher.assertArgsAreValid(),
            () => shorebirdValidator.validateFlavors(
              flavorArg: null,
              releasePlatform: ReleasePlatform.android,
            ),
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

          // Verify that the logger.chooseOne<Release> display function is
          // correct
          final displayFunctionCapture = verificationResult.captured.flattened
              .whereType<String Function(Release)>()
              .first;
          expect(displayFunctionCapture(release), equals(release.version));
        },
      );

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
              '''No ${releasePlatform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
            ),
          ).called(1);
        });
      });

      group('when prompting for releases and multiple exist', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
          ).thenAnswer(
            (_) async => [
              Release(
                id: 0,
                appId: appId,
                version: releaseVersion,
                flutterRevision: flutterRevision,
                flutterVersion: flutterVersion,
                displayName: releaseVersion,
                platformStatuses: const {releasePlatform: ReleaseStatus.active},
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
              Release(
                id: 1,
                appId: appId,
                version: releaseVersion,
                flutterRevision: flutterRevision,
                flutterVersion: flutterVersion,
                displayName: '2.0.0+1',
                platformStatuses: const {
                  ReleasePlatform.macos: ReleaseStatus.active,
                  ReleasePlatform.windows: ReleaseStatus.active,
                },
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
            ],
          );
        });

        test('only lists and uses releases '
            'for the specified platform', () async {
          await expectLater(runWithOverrides(command.run), completes);
          final captured =
              verify(
                    () => logger.chooseOne<Release>(
                      any(),
                      choices: captureAny(named: 'choices'),
                      display: any(named: 'display'),
                    ),
                  ).captured.single
                  as List<Release>;

          expect(captured.length, equals(1));
          expect(captured.first.version, equals(releaseVersion));

          verify(
            () => patcher.buildPatchArtifact(releaseVersion: releaseVersion),
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
                platformStatuses: const {releasePlatform: ReleaseStatus.active},
                createdAt: DateTime(2023),
                updatedAt: DateTime(2023),
              ),
            );
          });

          test(
            'builds app twice if release flutter version is not default',
            () async {
              final exitCode = await runWithOverrides(command.run);
              expect(exitCode, equals(ExitCode.success.code));

              verifyInOrder([
                () => logger.warn(
                  any(
                    that: startsWith(
                      'The release version to patch was not specified.',
                    ),
                  ),
                ),
                () => patcher.buildPatchArtifact(),
                () => patcher.extractReleaseVersionFromArtifact(any()),
                () => shorebirdFlutter.installRevision(
                  revision: releaseFlutterRevision,
                ),
                () => shorebirdEnv.copyWith(
                  flutterRevisionOverride: releaseFlutterRevision,
                ),
                () =>
                    patcher.buildPatchArtifact(releaseVersion: releaseVersion),
                () => patcher.updatedCreatePatchMetadata(
                  any(
                    that: isA<CreatePatchMetadata>().having(
                      (m) => m.inferredReleaseVersion,
                      'inferredReleaseVersion',
                      isTrue,
                    ),
                  ),
                ),
              ]);
            },
          );

          test(
            'updates cache with both default and release Flutter revisions',
            () async {
              await runWithOverrides(command.run);

              verifyInOrder([
                cache.updateAll,
                () => shorebirdEnv.copyWith(
                  flutterRevisionOverride: releaseFlutterRevision,
                ),
                cache.updateAll,
              ]);
            },
          );
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

    group('when --no-confirm is specified', () {
      setUp(() {
        when(() => argResults['no-confirm']).thenReturn(true);
      });

      test('does not prompt for confirmation', () async {
        await runWithOverrides(command.run);
        verifyNever(() => logger.confirm(any()));
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
            platformStatuses: const {releasePlatform: ReleaseStatus.draft},
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
          () => logger.err('''
Release ${release.version} is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.'''),
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
            platformStatuses: const {ReleasePlatform.ios: ReleaseStatus.active},
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

    group('when no platform argument is provided', () {
      setUp(() {
        when(() => argResults['platforms']).thenReturn(const <String>[]);
      });

      test('fails and log the correct message', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.usage.code));

        verify(
          () => logger.err(
            '''No platforms were provided. Use the --platforms argument to provide one or more platforms''',
          ),
        ).called(1);
      });
    });
  });

  group('sortByUpdatedAt', () {
    test('sorts versions correctly', () {
      expect(
        [
          _FakeRelease(updatedAt: DateTime(2025, 05, 15)),
          _FakeRelease(updatedAt: DateTime(2025, 04, 15)),
          _FakeRelease(updatedAt: DateTime(2021, 09, 25)),
          _FakeRelease(updatedAt: DateTime(2024)),
        ]..sortByUpdatedAt(),
        equals([
          _FakeRelease(updatedAt: DateTime(2021, 09, 25)),
          _FakeRelease(updatedAt: DateTime(2024)),
          _FakeRelease(updatedAt: DateTime(2025, 04, 15)),
          _FakeRelease(updatedAt: DateTime(2025, 05, 15)),
        ]),
      );
    });
  });
}
