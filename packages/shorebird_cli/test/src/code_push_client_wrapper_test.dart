import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group('scoped', () {
    late Auth auth;
    late http.Client httpClient;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;

    setUp(() {
      auth = MockAuth();
      httpClient = MockHttpClient();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();

      when(() => auth.client).thenReturn(httpClient);
      when(() => shorebirdEnv.hostedUri).thenReturn(
        Uri.parse('http://example.com'),
      );
    });

    test('creates instance from scoped Auth and ShorebirdEnvironment', () {
      final instance = runScoped(
        () => codePushClientWrapper,
        values: {
          codePushClientWrapperRef,
          authRef.overrideWith(() => auth),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
      expect(
        instance.codePushClient.hostedUri,
        Uri.parse('http://example.com'),
      );
      verify(() => auth.client).called(1);
    });
  });

  group(CodePushClientWrapper, () {
    Matcher exitsWithCode(ExitCode exitcode) => throwsA(
          isA<ProcessExit>().having(
            (e) => e.exitCode,
            'exitCode',
            exitcode.code,
          ),
        );
    const appId = 'test-app-id';
    final app = AppMetadata(
      appId: appId,
      displayName: 'Test App',
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const track = DeploymentTrack.production;
    final channel = Channel(id: 0, appId: appId, name: track.channel);
    const patchId = 1;
    const patchNumber = 2;
    const patch = Patch(id: patchId, number: patchNumber);
    const releasePlatform = ReleasePlatform.ios;
    const releaseId = 123;
    const arch = Arch.arm64;
    const flutterRevision = '123';
    const displayName = 'TestApp';
    const releaseVersion = '1.0.0';
    final release = Release(
      id: 1,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      displayName: displayName,
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final partchArtifactBundle = PatchArtifactBundle(
      arch: arch.name,
      path: 'path',
      hash: '',
      size: 4,
    );
    final patchArtifactBundles = {arch: partchArtifactBundle};
    const archMap = {
      arch: ArchMetadata(
        path: 'arm64-v8a',
        arch: 'aarch64',
        enginePath: 'android_release_arm64',
      ),
    };
    const releaseArtifact = ReleaseArtifact(
      id: 1,
      releaseId: releaseId,
      arch: 'aarch64',
      platform: releasePlatform,
      hash: 'asdf',
      size: 4,
      url: 'url',
    );

    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late CodePushClientWrapper codePushClientWrapper;
    late Platform platform;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      codePushClient = MockCodePushClient();
      logger = MockLogger();
      platform = MockPlatform();
      progress = MockProgress();

      codePushClientWrapper = runWithOverrides(
        () => CodePushClientWrapper(codePushClient: codePushClient),
      );

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.script).thenReturn(
        Uri.file(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );
    });

    group('app', () {
      group('createApp', () {
        test('prompts for displayName when not provided', () async {
          const appName = 'test app';
          const app = App(id: appId, displayName: 'Test App');
          when(() => logger.prompt(any())).thenReturn(appName);
          when(() => codePushClient.createApp(displayName: appName)).thenAnswer(
            (_) async => app,
          );

          await runWithOverrides(
            () => codePushClientWrapper.createApp(),
          );

          verify(() => logger.prompt(any())).called(1);
          verify(
            () => codePushClient.createApp(displayName: appName),
          ).called(1);
        });

        test('does not prompt for displayName when not provided', () async {
          const appName = 'test app';
          const app = App(id: appId, displayName: 'Test App');
          when(() => codePushClient.createApp(displayName: appName)).thenAnswer(
            (_) async => app,
          );

          await runWithOverrides(
            () => codePushClientWrapper.createApp(appName: appName),
          );

          verifyNever(() => logger.prompt(any()));
          verify(
            () => codePushClient.createApp(displayName: appName),
          ).called(1);
        });
      });

      group('getApps', () {
        test('exits with code 70 when getting apps fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getApps()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getApps(),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test(
          '''prints upgrade message when client throws CodePushUpgradeRequiredException''',
          () async {
            when(codePushClient.getApps).thenThrow(
              const CodePushUpgradeRequiredException(
                message: 'upgrade required',
              ),
            );
            await expectLater(
              () async => runWithOverrides(
                () => codePushClientWrapper.getApps(),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(() => progress.fail()).called(1);
            verify(
              () => logger.err('Your version of shorebird is out of date.'),
            ).called(1);
            verify(
              () => logger.info(
                '''Run ${lightCyan.wrap('shorebird upgrade')} to get the latest version.''',
              ),
            ).called(1);
          },
        );

        test('returns apps on success', () async {
          when(() => codePushClient.getApps()).thenAnswer((_) async => [app]);

          final apps = await runWithOverrides(
            () => codePushClientWrapper.getApps(),
          );

          expect(apps, equals([app]));
          verify(() => progress.complete()).called(1);
        });
      });

      group('getApp', () {
        test('exits with code 70 when getting app fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getApps()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 when app does not exist', () async {
          when(() => codePushClient.getApps()).thenAnswer((_) async => []);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.complete()).called(1);
          verify(
            () => logger.err(
              any(that: contains('Could not find app with id: "$appId"')),
            ),
          ).called(1);
        });

        test('returns app when app exists', () async {
          when(() => codePushClient.getApps()).thenAnswer((_) async => [app]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getApp(appId: appId),
          );

          expect(result, app);
          verify(() => progress.complete()).called(1);
        });
      });

      group('maybeGetApp', () {
        test('exits with code 70 when fetching apps fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getApps()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('succeeds if app does not exist', () async {
          when(() => codePushClient.getApps()).thenAnswer((_) async => []);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
          verifyNever(() => logger.err(any()));
        });

        test('returns app when app exists', () async {
          when(() => codePushClient.getApps()).thenAnswer((_) async => [app]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          expect(result, app);
          verify(() => progress.complete()).called(1);
        });
      });
    });

    group('channel', () {
      group('maybeGetChannel', () {
        test('exits with code 70 when fetching channels fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetChannel(
                appId: appId,
                name: track.channel,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns null when channel does not exist', () async {
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenAnswer((_) async => []);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetChannel(
              appId: appId,
              name: track.channel,
            ),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
        });

        test('returns channel when channel exists', () async {
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [channel]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetChannel(
              appId: appId,
              name: track.channel,
            ),
          );

          expect(result, channel);
          verify(() => progress.complete()).called(1);
        });
      });

      group('createChannel', () {
        test('exits with code 70 when creating channel fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createChannel(
              appId: any(named: 'appId'),
              channel: any(named: 'channel'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createChannel(
                appId: appId,
                name: track.channel,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns channel when channel is successfully created', () async {
          when(
            () => codePushClient.createChannel(
              appId: appId,
              channel: track.channel,
            ),
          ).thenAnswer((_) async => channel);

          final result = await runWithOverrides(
            () => codePushClientWrapper.createChannel(
              appId: appId,
              name: track.channel,
            ),
          );

          expect(result, channel);
          verify(() => progress.complete()).called(1);
        });
      });
    });

    group('release', () {
      group('ensureReleaseIsIsNotActive', () {
        test(
          '''exits with code 70 if release is in an active state for the given platform''',
          () {
            expect(
              () => runWithOverrides(
                () => codePushClientWrapper.ensureReleaseIsNotActive(
                  release: Release(
                    id: releaseId,
                    appId: appId,
                    version: releaseVersion,
                    flutterRevision: flutterRevision,
                    displayName: displayName,
                    platformStatuses: {
                      releasePlatform: ReleaseStatus.active,
                    },
                    createdAt: DateTime(2023),
                    updatedAt: DateTime(2023),
                  ),
                  platform: releasePlatform,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err(
                '''
It looks like you have an existing ios release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.''',
              ),
            ).called(1);
          },
        );

        test(
          '''completes without error if release has no status for the given platform''',
          () async {
            await expectLater(
              runWithOverrides(
                () async => codePushClientWrapper.ensureReleaseIsNotActive(
                  release: Release(
                    id: releaseId,
                    appId: appId,
                    version: releaseVersion,
                    flutterRevision: flutterRevision,
                    displayName: displayName,
                    platformStatuses: {},
                    createdAt: DateTime(2023),
                    updatedAt: DateTime(2023),
                  ),
                  platform: releasePlatform,
                ),
              ),
              completes,
            );
          },
        );

        test(
          '''completes without error if release has draft status for the given platform''',
          () async {
            await expectLater(
              runWithOverrides(
                () async => codePushClientWrapper.ensureReleaseIsNotActive(
                  release: Release(
                    id: releaseId,
                    appId: appId,
                    version: releaseVersion,
                    flutterRevision: flutterRevision,
                    displayName: displayName,
                    platformStatuses: {releasePlatform: ReleaseStatus.draft},
                    createdAt: DateTime(2023),
                    updatedAt: DateTime(2023),
                  ),
                  platform: releasePlatform,
                ),
              ),
              completes,
            );
          },
        );
      });

      group('getReleases', () {
        test('exits with code 70 when fetching release fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleases(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns releases on success', () async {
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [release]);

          final releases = await runWithOverrides(
            () => codePushClientWrapper.getReleases(appId: appId),
          );

          expect(releases, equals([release]));

          verify(() => progress.complete()).called(1);
        });

        test('forwards sideloadableOnly value to codePushClient', () async {
          when(
            () => codePushClient.getReleases(
              appId: any(named: 'appId'),
              sideloadableOnly: any(named: 'sideloadableOnly'),
            ),
          ).thenAnswer((_) async => []);

          await runWithOverrides(
            () => codePushClientWrapper.getReleases(
              appId: appId,
              sideloadableOnly: true,
            ),
          );

          verify(
            () => codePushClient.getReleases(
              appId: appId,
              sideloadableOnly: true,
            ),
          );
        });
      });

      group('getRelease', () {
        test('exits with code 70 when fetching release fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getRelease(
                appId: appId,
                releaseVersion: releaseVersion,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 when release does not exist', () async {
          when(() => codePushClient.getReleases(appId: any(named: 'appId')))
              .thenAnswer((_) async => []);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getRelease(
                appId: appId,
                releaseVersion: releaseVersion,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.complete()).called(1);
          verify(
            () => logger.err(
              any(that: contains('Release not found: "$releaseVersion"')),
            ),
          ).called(1);
        });

        test('returns release when release exists', () async {
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [release]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getRelease(
              appId: appId,
              releaseVersion: releaseVersion,
            ),
          );

          expect(result, release);
          verify(() => progress.complete()).called(1);
        });
      });

      group('maybeGetRelease', () {
        test('exits with code 70 when fetching releases fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetRelease(
                appId: appId,
                releaseVersion: releaseVersion,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('succeeds if release does not exist', () async {
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => []);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetRelease(
              appId: appId,
              releaseVersion: releaseVersion,
            ),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
          verifyNever(() => logger.err(any()));
        });

        test('returns release when release exists', () async {
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [release]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetRelease(
              appId: appId,
              releaseVersion: releaseVersion,
            ),
          );

          expect(result, release);
          verify(() => progress.complete()).called(1);
        });
      });

      group('createRelease', () {
        test('exits with code 70 when creating release fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createRelease(
              appId: any(named: 'appId'),
              version: any(named: 'version'),
              flutterRevision: any(named: 'flutterRevision'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createRelease(
                appId: appId,
                version: releaseVersion,
                flutterRevision: flutterRevision,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns release when release is successfully created', () async {
          when(
            () => codePushClient.createRelease(
              appId: any(named: 'appId'),
              version: any(named: 'version'),
              flutterRevision: any(named: 'flutterRevision'),
            ),
          ).thenAnswer((_) async => release);
          when(
            () => codePushClient.updateReleaseStatus(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
              status: any(named: 'status'),
            ),
          ).thenAnswer((_) async => {});

          final result = await runWithOverrides(
            () async => codePushClientWrapper.createRelease(
              appId: appId,
              version: releaseVersion,
              flutterRevision: flutterRevision,
              platform: releasePlatform,
            ),
          );

          expect(result, release);
          verify(
            () => codePushClient.updateReleaseStatus(
              appId: appId,
              releaseId: result.id,
              platform: releasePlatform,
              status: ReleaseStatus.draft,
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });
      });
    });

    group('release artifact', () {
      group('getReleaseArtifacts', () {
        test('exits with code 70 if fetching release artifact fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                architectures: archMap,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 if release artifact does not exist', () async {
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => []);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                architectures: archMap,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(
            () => progress.fail(
              '''No artifact found for architecture aarch64 in release $releaseId''',
            ),
          ).called(1);
        });

        test('returns release artifacts when release artifacts exist',
            () async {
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => [releaseArtifact]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              architectures: archMap,
              platform: releasePlatform,
            ),
          );

          expect(result, {arch: releaseArtifact});
          verify(() => progress.complete()).called(1);
        });
      });

      group('getReleaseArtifact', () {
        test('exits with code 70 if fetching release artifact fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifact(
                appId: app.appId,
                releaseId: releaseId,
                arch: arch.name,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 if release artifact does not exist', () async {
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => []);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifact(
                appId: app.appId,
                releaseId: releaseId,
                arch: arch.name,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(
            () => progress.fail(
              '''No artifact found for architecture arm64 in release $releaseId''',
            ),
          ).called(1);
        });

        test(
          'returns release artifact if release artifact exists',
          () async {
            when(
              () => codePushClient.getReleaseArtifacts(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
              ),
            ).thenAnswer((_) async => [releaseArtifact]);

            final result = await runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifact(
                appId: app.appId,
                releaseId: releaseId,
                arch: arch.name,
                platform: releasePlatform,
              ),
            );

            expect(result, releaseArtifact);
            verify(() => progress.complete()).called(1);
          },
        );
      });

      group('maybeGetReleaseArtifact', () {
        test('exits with code 70 if fetching release artifact fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetReleaseArtifact(
                appId: app.appId,
                releaseId: releaseId,
                arch: arch.name,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(error)).called(1);
        });

        test('returns null if release artifact does not exist', () async {
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => []);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetReleaseArtifact(
              appId: app.appId,
              releaseId: releaseId,
              arch: arch.name,
              platform: releasePlatform,
            ),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
        });

        test(
          'returns release artifact if release artifact exists',
          () async {
            when(
              () => codePushClient.getReleaseArtifacts(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
              ),
            ).thenAnswer((_) async => [releaseArtifact]);

            final result = await runWithOverrides(
              () => codePushClientWrapper.maybeGetReleaseArtifact(
                appId: app.appId,
                releaseId: releaseId,
                arch: arch.name,
                platform: releasePlatform,
              ),
            );

            expect(result, releaseArtifact);
            verify(() => progress.complete()).called(1);
          },
        );
      });

      group('createAndroidReleaseArtifacts', () {
        final aabPath = p.join('path', 'to', 'app.aab');

        Directory setUpTempDir({String? flavor}) {
          final tempDir = Directory.systemTemp.createTempSync();
          File(p.join(tempDir.path, aabPath)).createSync(recursive: true);
          for (final archMetadata
              in ShorebirdBuildMixin.allAndroidArchitectures.values) {
            final artifactPath = p.join(
              tempDir.path,
              'build',
              'app',
              'intermediates',
              'stripped_native_libs',
              flavor != null ? '${flavor}Release' : 'release',
              'out',
              'lib',
              archMetadata.path,
              'libapp.so',
            );
            File(artifactPath).createSync(recursive: true);
          }
          return tempDir;
        }

        setUp(() {
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
        });

        test('exits with code 70 when artifact creation fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(error);
          final tempDir = setUpTempDir();

          await IOOverrides.runZoned(
            () async => expectLater(
              () async => runWithOverrides(
                () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  projectRoot: tempDir.path,
                  aabPath: p.join(tempDir.path, aabPath),
                  architectures: ShorebirdBuildMixin.allAndroidArchitectures,
                ),
              ),
              exitsWithCode(ExitCode.software),
            ),
            getCurrentDirectory: () => tempDir,
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test('exits with code 70 when aab artifact creation fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath', that: endsWith('aab')),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(error);
          final tempDir = setUpTempDir();

          await IOOverrides.runZoned(
            () async => expectLater(
              () async => runWithOverrides(
                () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  projectRoot: tempDir.path,
                  aabPath: p.join(tempDir.path, aabPath),
                  architectures: ShorebirdBuildMixin.allAndroidArchitectures,
                ),
              ),
              exitsWithCode(ExitCode.software),
            ),
            getCurrentDirectory: () => tempDir,
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test('logs message when uploading release artifact that already exists',
            () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: tempDir.path,
                aabPath: p.join(tempDir.path, aabPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          // 1 for each arch, 1 for the aab
          final numArtifactsUploaded =
              ShorebirdBuildMixin.allAndroidArchitectures.values.length + 1;
          verify(
            () => logger.info(any(that: contains('already exists'))),
          ).called(numArtifactsUploaded);
          verifyNever(() => progress.fail(error));
        });

        test('logs message when uploading aab that already exists', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath', that: endsWith('.aab')),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: tempDir.path,
                aabPath: p.join(tempDir.path, aabPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(
            () => logger.info(
              any(that: contains('aab artifact already exists, continuing...')),
            ),
          ).called(1);
          verifyNever(() => progress.fail(error));
        });

        test('completes successfully when all artifacts are created', () async {
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: tempDir.path,
                aabPath: p.join(tempDir.path, aabPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('completes succesfully when a flavor is provided', () async {
          const flavorName = 'myFlavor';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
          final tempDir = setUpTempDir(flavor: flavorName);

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: tempDir.path,
                aabPath: p.join(tempDir.path, aabPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
                flavor: flavorName,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(
            () => codePushClient.createReleaseArtifact(
              appId: app.appId,
              artifactPath: any(
                named: 'artifactPath',
                that: contains(flavorName),
              ),
              releaseId: releaseId,
              arch: any(named: 'arch'),
              platform: releasePlatform,
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).called(ShorebirdBuildMixin.allAndroidArchitectures.length);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });
      });

      group('createAndroidArchiveReleaseArtifacts', () {
        const buildNumber = '1.0';

        final aarDir = p.join(
          'build',
          'host',
          'outputs',
          'repo',
          'com',
          'example',
          'my_flutter_module',
          'flutter_release',
          buildNumber,
        );
        final aarPath = p.join(aarDir, 'flutter_release-$buildNumber.aar');
        final extractedAarPath = p.join(aarDir, 'flutter_release-$buildNumber');

        Directory setUpTempDir({String? flavor}) {
          final tempDir = Directory.systemTemp.createTempSync();
          for (final archMetadata
              in ShorebirdBuildMixin.allAndroidArchitectures.values) {
            final artifactPath = p.join(
              tempDir.path,
              extractedAarPath,
              'jni',
              archMetadata.path,
              'libapp.so',
            );
            File(artifactPath).createSync(recursive: true);
          }
          File(p.join(tempDir.path, aarPath)).createSync(recursive: true);
          return tempDir;
        }

        setUp(() {
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
        });

        test('exits with code 70 when artifact creation fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(error);
          final tempDir = setUpTempDir();

          await IOOverrides.runZoned(
            () async => expectLater(
              () async => runWithOverrides(
                () async =>
                    codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  aarPath: p.join(tempDir.path, aarPath),
                  extractedAarDir: p.join(tempDir.path, extractedAarPath),
                  architectures: ShorebirdBuildMixin.allAndroidArchitectures,
                ),
              ),
              exitsWithCode(ExitCode.software),
            ),
            getCurrentDirectory: () => tempDir,
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test('exits with code 70 when aar artifact creation fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath', that: endsWith('aar')),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(error);
          final tempDir = setUpTempDir();

          await IOOverrides.runZoned(
            () async => expectLater(
              () async => runWithOverrides(
                () async =>
                    codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  aarPath: p.join(tempDir.path, aarPath),
                  extractedAarDir: p.join(tempDir.path, extractedAarPath),
                  architectures: ShorebirdBuildMixin.allAndroidArchitectures,
                ),
              ),
              exitsWithCode(ExitCode.software),
            ),
            getCurrentDirectory: () => tempDir,
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test('logs message when uploading release artifact that already exists',
            () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                aarPath: p.join(tempDir.path, aarPath),
                extractedAarDir: p.join(tempDir.path, extractedAarPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          // 1 for each arch, 1 for the aab
          final numArtifactsUploaded =
              ShorebirdBuildMixin.allAndroidArchitectures.values.length + 1;
          verify(
            () => logger.info(any(that: contains('already exists'))),
          ).called(numArtifactsUploaded);
          verifyNever(() => progress.fail(error));
        });

        test('logs message when uploading aar that already exists', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath', that: endsWith('.aar')),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                aarPath: p.join(tempDir.path, aarPath),
                extractedAarDir: p.join(tempDir.path, extractedAarPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(
            () => logger.info(
              any(that: contains('aar artifact already exists, continuing...')),
            ),
          ).called(1);
          verifyNever(() => progress.fail(error));
        });

        test('completes successfully when all artifacts are created', () async {
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
          final tempDir = setUpTempDir();

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                aarPath: p.join(tempDir.path, aarPath),
                extractedAarDir: p.join(tempDir.path, extractedAarPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('completes succesfully when a flavor is provided', () async {
          const flavorName = 'myFlavor';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(named: 'artifactPath'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenAnswer((_) async => {});
          final tempDir = setUpTempDir(flavor: flavorName);

          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                aarPath: p.join(tempDir.path, aarPath),
                extractedAarDir: p.join(tempDir.path, extractedAarPath),
                architectures: ShorebirdBuildMixin.allAndroidArchitectures,
              ),
              getCurrentDirectory: () => tempDir,
            ),
          );

          verify(
            () => codePushClient.createReleaseArtifact(
              appId: app.appId,
              artifactPath: any(named: 'artifactPath'),
              releaseId: releaseId,
              arch: any(named: 'arch'),
              platform: releasePlatform,
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).called(ShorebirdBuildMixin.allAndroidArchitectures.length + 1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });
      });
    });

    group('createIosReleaseArtifacts', () {
      final xcarchivePath = p.join('path', 'to', 'app.xcarchive');
      final runnerPath = p.join('path', 'to', 'runner.app');

      Directory setUpTempDir({String? flavor}) {
        final tempDir = Directory.systemTemp.createTempSync();
        Directory(p.join(tempDir.path, xcarchivePath))
            .createSync(recursive: true);
        Directory(p.join(tempDir.path, runnerPath)).createSync(recursive: true);
        return tempDir;
      }

      setUp(() {
        when(
          () => codePushClient.createReleaseArtifact(
            appId: any(named: 'appId'),
            artifactPath: any(named: 'artifactPath'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenAnswer((_) async => {});
      });

      test('exits with code 70 when xcarchive artifact creation fails',
          () async {
        const error = 'something went wrong';
        when(
          () => codePushClient.createReleaseArtifact(
            appId: any(named: 'appId'),
            artifactPath:
                any(named: 'artifactPath', that: endsWith('.xcarchive.zip')),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenThrow(error);
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () async => expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(tempDir.path, xcarchivePath),
                runnerPath: p.join(tempDir.path, runnerPath),
                isCodesigned: true,
              ),
            ),
            exitsWithCode(ExitCode.software),
          ),
          getCurrentDirectory: () => tempDir,
        );

        verify(() => progress.fail(any(that: contains(error)))).called(1);
      });

      test('exits with code 70 when uploading xcarchive that already exists',
          () async {
        const error = 'something went wrong';
        when(
          () => codePushClient.createReleaseArtifact(
            appId: any(named: 'appId'),
            artifactPath:
                any(named: 'artifactPath', that: endsWith('.xcarchive.zip')),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenThrow(const CodePushConflictException(message: error));
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () async => expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(tempDir.path, xcarchivePath),
                runnerPath: p.join(tempDir.path, runnerPath),
                isCodesigned: false,
              ),
            ),
            exitsWithCode(ExitCode.software),
          ),
          getCurrentDirectory: () => tempDir,
        );

        verify(() => progress.fail(any(that: contains(error)))).called(1);
      });

      test('exits with code 70 when xcarchive artifact creation fails',
          () async {
        const error = 'something went wrong';
        when(
          () => codePushClient.createReleaseArtifact(
            appId: any(named: 'appId'),
            artifactPath: any(
              named: 'artifactPath',
              that: endsWith('runner.app.zip'),
            ),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenThrow(error);
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () async => expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(tempDir.path, xcarchivePath),
                runnerPath: p.join(tempDir.path, runnerPath),
                isCodesigned: false,
              ),
            ),
            exitsWithCode(ExitCode.software),
          ),
          getCurrentDirectory: () => tempDir,
        );

        verify(() => progress.fail(any(that: contains(error)))).called(1);
      });

      test('completes successfully when artifact is created', () async {
        when(
          () => codePushClient.createReleaseArtifact(
            appId: any(named: 'appId'),
            artifactPath: any(named: 'artifactPath'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenAnswer((_) async => {});
        final tempDir = setUpTempDir();

        await runWithOverrides(
          () async => IOOverrides.runZoned(
            () async => codePushClientWrapper.createIosReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              xcarchivePath: p.join(tempDir.path, xcarchivePath),
              runnerPath: p.join(tempDir.path, runnerPath),
              isCodesigned: true,
            ),
            getCurrentDirectory: () => tempDir,
          ),
        );

        verify(() => progress.complete()).called(1);
        verifyNever(() => progress.fail(any()));
      });
    });

    group('createIosFrameworkReleaseArtifacts', () {
      final frameworkPath = p.join('path', 'to', 'App.xcframework');

      Directory setUpTempDir({String? flavor}) {
        final tempDir = Directory.systemTemp.createTempSync();
        Directory(p.join(tempDir.path, frameworkPath))
            .createSync(recursive: true);
        return tempDir;
      }

      test(
        'exits with code 70 when creating xcframework artifact fails',
        () async {
          when(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath'),
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
            ),
          ).thenThrow(
            Exception('oh no'),
          );
          final tempDir = setUpTempDir();

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                appFrameworkPath: p.join(tempDir.path, frameworkPath),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
        },
      );

      test('completes successfully when release artifact is created', () async {
        when(
          () => codePushClient.createReleaseArtifact(
            artifactPath: any(named: 'artifactPath'),
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
          ),
        ).thenAnswer((_) async => {});
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () async => expectLater(
            runWithOverrides(
              () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                appFrameworkPath: p.join(tempDir.path, frameworkPath),
              ),
            ),
            completes,
          ),
          getCurrentDirectory: () => tempDir,
        );
      });
    });

    group('updateReleaseStatus', () {
      test(
        'exits with code 70 when updating release status fails',
        () async {
          when(
            () => codePushClient.updateReleaseStatus(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
              status: any(named: 'status'),
            ),
          ).thenThrow(Exception('oh no'));

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.updateReleaseStatus(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                status: ReleaseStatus.active,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
        },
      );

      test('completes when updating release status succeeds', () async {
        when(
          () => codePushClient.updateReleaseStatus(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            status: any(named: 'status'),
          ),
        ).thenAnswer((_) async => {});

        await runWithOverrides(
          () => codePushClientWrapper.updateReleaseStatus(
            appId: app.appId,
            releaseId: releaseId,
            platform: releasePlatform,
            status: ReleaseStatus.active,
          ),
        );

        verify(
          () => codePushClient.updateReleaseStatus(
            appId: app.appId,
            releaseId: releaseId,
            platform: releasePlatform,
            status: ReleaseStatus.active,
          ),
        ).called(1);
        verify(() => progress.complete()).called(1);
      });
    });

    group('patch', () {
      group('createPatch', () {
        test('exits with code 70 when creating patch fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createPatch(
                appId: appId,
                releaseId: releaseId,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns patch when patch is successfully created', () async {
          when(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
            ),
          ).thenAnswer((_) async => patch);

          final result = await runWithOverrides(
            () => codePushClientWrapper.createPatch(
              appId: appId,
              releaseId: releaseId,
            ),
          );

          expect(result, patch);
          verify(() => progress.complete()).called(1);
        });
      });

      group('promotePatch', () {
        test('exits with code 70 when promoting patch fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.promotePatch(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.promotePatch(
                appId: appId,
                patchId: patchId,
                channel: channel,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes progress when patch is promoted', () async {
          when(
            () => codePushClient.promotePatch(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenAnswer((_) async => patch);

          await runWithOverrides(
            () => codePushClientWrapper.promotePatch(
              appId: appId,
              patchId: patchId,
              channel: channel,
            ),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('createPatchArtifacts', () {
        test(
          'exits with code 70 when creating patch artifact fails',
          () async {
            const error = 'something went wrong';
            when(
              () => codePushClient.createPatchArtifact(
                appId: any(named: 'appId'),
                patchId: any(named: 'patchId'),
                artifactPath: any(named: 'artifactPath'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
                hash: any(named: 'hash'),
              ),
            ).thenThrow(error);

            await expectLater(
              () async => runWithOverrides(
                () => codePushClientWrapper.createPatchArtifacts(
                  appId: appId,
                  patch: patch,
                  platform: releasePlatform,
                  patchArtifactBundles: patchArtifactBundles,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(() => progress.fail(error)).called(1);
          },
        );

        test('creates artifacts successfully', () async {
          when(
            () => codePushClient.createPatchArtifact(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              artifactPath: any(named: 'artifactPath'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.createPatchArtifacts(
              appId: appId,
              patch: patch,
              platform: releasePlatform,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(() => progress.complete()).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              appId: appId,
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: releasePlatform,
              hash: partchArtifactBundle.hash,
            ),
          ).called(1);
        });
      });

      group('publishPatch', () {
        setUp(() {
          when(
            () => codePushClient.createPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer((_) async => patch);
          when(
            () => codePushClient.createPatchArtifact(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              artifactPath: any(named: 'artifactPath'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
            ),
          ).thenAnswer((_) async {});
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenAnswer((_) async => [channel]);
          when(
            () => codePushClient.promotePatch(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenAnswer((_) async => patch);
        });

        test('makes expected calls to code push client', () async {
          await runWithOverrides(
            () => codePushClientWrapper.publishPatch(
              appId: appId,
              releaseId: releaseId,
              platform: releasePlatform,
              track: track,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
            ),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              appId: appId,
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: releasePlatform,
              hash: partchArtifactBundle.hash,
            ),
          ).called(1);
          verify(() => codePushClient.getChannels(appId: appId)).called(1);
          verifyNever(
            () => codePushClient.createChannel(
              appId: any(named: 'appId'),
              channel: any(named: 'channel'),
            ),
          );
          verify(
            () => codePushClient.promotePatch(
              appId: appId,
              patchId: patchId,
              channelId: channel.id,
            ),
          ).called(1);
        });

        test('creates channel if none exists', () async {
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenAnswer((_) async => []);

          when(
            () => codePushClient.createChannel(
              appId: any(named: 'appId'),
              channel: any(named: 'channel'),
            ),
          ).thenAnswer((_) async => channel);

          await runWithOverrides(
            () => codePushClientWrapper.publishPatch(
              appId: appId,
              releaseId: releaseId,
              platform: releasePlatform,
              track: track,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
            ),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              appId: appId,
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: releasePlatform,
              hash: partchArtifactBundle.hash,
            ),
          ).called(1);
          verify(() => codePushClient.getChannels(appId: appId)).called(1);
          verify(
            () => codePushClient.createChannel(
              appId: appId,
              channel: track.channel,
            ),
          ).called(1);
          verify(
            () => codePushClient.promotePatch(
              appId: appId,
              patchId: patchId,
              channelId: channel.id,
            ),
          ).called(1);
        });

        test('prints patch number on success', () async {
          await runWithOverrides(
            () => codePushClientWrapper.publishPatch(
              appId: appId,
              releaseId: releaseId,
              platform: releasePlatform,
              track: track,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(
            () => logger.success(any(that: contains('Published Patch 2!'))),
          ).called(1);
        });
      });
    });
  });
}
