import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'matchers.dart';
import 'mocks.dart';

void main() {
  group('scoped', () {
    late Auth auth;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      auth = MockAuth();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => auth.client).thenReturn(httpClient);
      when(
        () => shorebirdEnv.hostedUri,
      ).thenReturn(Uri.parse('http://example.com'));
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdFlutter.getVersionForRevision(
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => '3.22.0');
    });

    test('creates correct instance from environment', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(json.encode(const GetAppsResponse(apps: []).toJson())),
          ),
          HttpStatus.ok,
        ),
      );
      final instance = runScoped(
        () => codePushClientWrapper,
        values: {
          codePushClientWrapperRef,
          authRef.overrideWith(() => auth),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );

      expect(
        instance.codePushClient.hostedUri,
        Uri.parse('http://example.com'),
      );
      verify(() => auth.client).called(1);

      await runScoped(
        instance.getApps,
        values: {loggerRef.overrideWith(() => logger)},
      );

      final request =
          verify(() => httpClient.send(captureAny())).captured.first
              as http.BaseRequest;

      expect(request.headers['x-cli-version'], equals(packageVersion));
    });
  });

  group(CodePushClientWrapper, () {
    const appId = 'test-app-id';
    final app = AppMetadata(
      appId: appId,
      displayName: 'Test App',
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const track = DeploymentTrack.stable;
    final channel = Channel(id: 0, appId: appId, name: track.channel);
    const patchId = 1;
    const patchNumber = 2;
    const patch = Patch(id: patchId, number: patchNumber);
    const releasePlatform = ReleasePlatform.ios;
    const releaseId = 123;
    const arch = Arch.arm64;
    const flutterRevision = '123';
    const flutterVersion = '3.22.0';
    const displayName = 'TestApp';
    const releaseVersion = '1.0.0';
    final release = Release(
      id: 1,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      flutterVersion: flutterVersion,
      displayName: displayName,
      platformStatuses: const {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final patchArtifactBundle = PatchArtifactBundle(
      arch: arch.arch,
      path: 'path',
      hash: '',
      size: 4,
    );
    final patchArtifactBundles = {arch: patchArtifactBundle};
    const archs = [Arch.arm64];
    const releaseArtifact = ReleaseArtifact(
      id: 1,
      releaseId: releaseId,
      arch: 'aarch64',
      platform: releasePlatform,
      hash: 'asdf',
      size: 4,
      url: 'url',
      podfileLockHash: 'podfile-lock-hash',
      canSideload: true,
    );

    late CodePushClient codePushClient;
    late Ditto ditto;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late Progress progress;
    late CodePushClientWrapper codePushClientWrapper;
    late Platform platform;
    late Directory projectRoot;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          dittoRef.overrideWith(() => ditto),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
    });

    setUp(() {
      codePushClient = MockCodePushClient();
      ditto = MockDitto();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();

      codePushClientWrapper = runWithOverrides(
        () => CodePushClientWrapper(codePushClient: codePushClient),
      );

      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(
        () => ditto.archive(
          source: any(named: 'source'),
          destination: any(named: 'destination'),
        ),
      ).thenAnswer((_) async {});
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

      when(
        () => shorebirdFlutter.getVersionForRevision(
          flutterRevision: flutterRevision,
        ),
      ).thenAnswer((_) async => flutterVersion);
    });

    group('app', () {
      const organizationId = 123;

      group('createApp', () {
        test('prompts for displayName when not provided', () async {
          const appName = 'test app';
          const app = App(id: appId, displayName: 'Test App');
          when(() => logger.prompt(any())).thenReturn(appName);
          when(
            () => codePushClient.createApp(
              displayName: appName,
              organizationId: any(named: 'organizationId'),
            ),
          ).thenAnswer((_) async => app);

          await runWithOverrides(
            () =>
                codePushClientWrapper.createApp(organizationId: organizationId),
          );

          verify(() => logger.prompt(any())).called(1);
          verify(
            () => codePushClient.createApp(
              displayName: appName,
              organizationId: organizationId,
            ),
          ).called(1);
        });

        test('does not prompt for displayName when not provided', () async {
          const appName = 'test app';
          const app = App(id: appId, displayName: 'Test App');
          when(
            () => codePushClient.createApp(
              displayName: appName,
              organizationId: any(named: 'organizationId'),
            ),
          ).thenAnswer((_) async => app);

          await runWithOverrides(
            () => codePushClientWrapper.createApp(
              appName: appName,
              organizationId: organizationId,
            ),
          );

          verifyNever(() => logger.prompt(any()));
          verify(
            () => codePushClient.createApp(
              displayName: appName,
              organizationId: organizationId,
            ),
          ).called(1);
        });
      });

      group('getOrganizationMemberships', () {
        test(
          'exits with code 70 when getting organization memberships fails',
          () async {
            const error = 'something went wrong';
            when(
              () => codePushClient.getOrganizationMemberships(),
            ).thenThrow(error);

            await expectLater(
              () async => runWithOverrides(
                codePushClientWrapper.getOrganizationMemberships,
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(() => progress.fail(error)).called(1);
          },
        );

        test('returns organization memberships on success', () async {
          final expectedMemberships = [
            OrganizationMembership(
              organization: Organization.forTest(),
              role: OrganizationRole.admin,
            ),
            OrganizationMembership(
              organization: Organization.forTest(),
              role: OrganizationRole.member,
            ),
          ];
          when(
            () => codePushClient.getOrganizationMemberships(),
          ).thenAnswer((_) async => expectedMemberships);

          final memberships = await runWithOverrides(
            codePushClientWrapper.getOrganizationMemberships,
          );

          expect(memberships, equals(expectedMemberships));
          verify(() => progress.complete()).called(1);
        });
      });

      group('getApps', () {
        test('exits with code 70 when getting apps fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getApps()).thenThrow(error);

          await expectLater(
            () => runWithOverrides(codePushClientWrapper.getApps),
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
              () async =>
                  runWithOverrides(() => codePushClientWrapper.getApps()),
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
                    flutterVersion: flutterVersion,
                    displayName: displayName,
                    platformStatuses: const {
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
            final uri = ShorebirdWebConsole.appReleaseUri(appId, releaseId);

            verify(
              () => logger.err(
                '''
It looks like you have an existing ios release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.

You can manage this release in the ${link(uri: uri, message: 'Shorebird Console')}''',
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
                    flutterVersion: flutterVersion,
                    displayName: displayName,
                    platformStatuses: const {},
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
                    flutterVersion: flutterVersion,
                    displayName: displayName,
                    platformStatuses: const {
                      releasePlatform: ReleaseStatus.draft,
                    },
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
          when(
            () => codePushClient.getReleases(appId: any(named: 'appId')),
          ).thenAnswer((_) async => []);

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

      group('getReleasePatches', () {
        group('when getPatches request fails', () {
          setUp(() {
            when(
              () => codePushClient.getPatches(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
              ),
            ).thenThrow('something went wrong');
          });

          test('exits with code 70', () async {
            await expectLater(
              () async => runWithOverrides(
                () => codePushClientWrapper.getReleasePatches(
                  appId: appId,
                  releaseId: releaseId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(() => progress.fail(any())).called(1);
          });
        });

        group('when getPatches request succeeds', () {
          final patch = ReleasePatch(
            id: 0,
            number: 1,
            channel: DeploymentTrack.stable.channel,
            isRolledBack: false,
            artifacts: const [],
          );

          setUp(() {
            when(
              () => codePushClient.getPatches(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
              ),
            ).thenAnswer((_) async => [patch]);
          });

          test('returns list of patches', () async {
            final result = await runWithOverrides(
              () => codePushClientWrapper.getReleasePatches(
                appId: appId,
                releaseId: releaseId,
              ),
            );

            expect(result, equals([patch]));
            verify(() => progress.complete()).called(1);
          });
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
              flutterVersion: any(named: 'flutterVersion'),
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
              flutterVersion: any(named: 'flutterVersion'),
            ),
          ).thenAnswer((_) async => release);
          when(
            () => codePushClient.updateReleaseStatus(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
              status: any(named: 'status'),
            ),
          ).thenAnswer((_) async {});

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
                architectures: archs,
                platform: releasePlatform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('only returns release artifacts that exist', () async {
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => []);
          when(
            () => codePushClient.getReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: 'aarch64',
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => [releaseArtifact]);

          expect(
            await runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                architectures: Arch.values,
                platform: releasePlatform,
              ),
            ),
            equals({Arch.arm64: releaseArtifact}),
          );
        });

        test(
          'returns release artifacts when release artifacts exist',
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
                architectures: archs,
                platform: releasePlatform,
              ),
            );

            expect(result, {arch: releaseArtifact});
            verify(() => progress.complete()).called(1);
          },
        );
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
                arch: arch.arch,
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

        test('returns release artifact if release artifact exists', () async {
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
              arch: arch.arch,
              platform: releasePlatform,
            ),
          );

          expect(result, releaseArtifact);
          verify(() => progress.complete()).called(1);
        });
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
                arch: arch.arch,
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
              arch: arch.arch,
              platform: releasePlatform,
            ),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
        });

        test('returns release artifact if release artifact exists', () async {
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
              arch: arch.arch,
              platform: releasePlatform,
            ),
          );

          expect(result, releaseArtifact);
          verify(() => progress.complete()).called(1);
        });
      });

      group('createAndroidReleaseArtifacts', () {
        final aabPath = p.join('path', 'to', 'app.aab');

        void setUpProjectRoot({String? flavor}) {
          File(p.join(projectRoot.path, aabPath)).createSync(recursive: true);
          for (final archMetadata in Arch.values) {
            final artifactPath = p.join(
              projectRoot.path,
              'build',
              'app',
              'intermediates',
              'stripped_native_libs',
              flavor != null ? '${flavor}Release' : 'release',
              'out',
              'lib',
              archMetadata.androidBuildPath,
              'libapp.so',
            );
            File(artifactPath).createSync(recursive: true);
          }
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
        });

        test('exits with code 70 when artifacts cannot be found', () async {
          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: projectRoot.path,
                aabPath: p.join(projectRoot.path, aabPath),
                architectures: Arch.values,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(
            () => progress.fail(
              any(that: contains('Cannot find release build artifacts')),
            ),
          ).called(1);
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: projectRoot.path,
                aabPath: p.join(projectRoot.path, aabPath),
                architectures: Arch.values,
              ),
            ),
            exitsWithCode(ExitCode.software),
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: projectRoot.path,
                aabPath: p.join(projectRoot.path, aabPath),
                architectures: Arch.values,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test(
          'logs message when uploading release artifact that already exists',
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
                podfileLockHash: any(named: 'podfileLockHash'),
              ),
            ).thenThrow(const CodePushConflictException(message: error));
            setUpProjectRoot();

            await runWithOverrides(
              () => codePushClientWrapper.createAndroidReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                platform: releasePlatform,
                projectRoot: projectRoot.path,
                aabPath: p.join(projectRoot.path, aabPath),
                architectures: Arch.values,
              ),
            );

            // 1 for each arch, 1 for the aab
            final numArtifactsUploaded = Arch.values.length + 1;
            verify(
              () => logger.info(any(that: contains('already exists'))),
            ).called(numArtifactsUploaded);
            verifyNever(() => progress.fail(error));
          },
        );

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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          setUpProjectRoot();

          await runWithOverrides(
            () async => codePushClientWrapper.createAndroidReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              platform: releasePlatform,
              projectRoot: projectRoot.path,
              aabPath: p.join(projectRoot.path, aabPath),
              architectures: Arch.values,
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
          setUpProjectRoot();

          await runWithOverrides(
            () async => codePushClientWrapper.createAndroidReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              platform: releasePlatform,
              projectRoot: projectRoot.path,
              aabPath: p.join(projectRoot.path, aabPath),
              architectures: Arch.values,
            ),
          );

          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('completes successfully when a flavor is provided', () async {
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
          setUpProjectRoot(flavor: flavorName);

          await runWithOverrides(
            () async => codePushClientWrapper.createAndroidReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              platform: releasePlatform,
              projectRoot: projectRoot.path,
              aabPath: p.join(projectRoot.path, aabPath),
              architectures: Arch.values,
              flavor: flavorName,
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
              podfileLockHash: null,
            ),
          ).called(Arch.values.length);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });
      });

      group('createWindowsReleaseArtifacts', () {
        late File releaseZip;
        setUp(() {
          releaseZip = File(
            p.join(projectRoot.path, 'path', 'to', 'release.zip'),
          )..createSync(recursive: true);
        });

        group('when release artifact already exists', () {
          setUp(() {
            when(
              () => codePushClient.createReleaseArtifact(
                artifactPath: any(named: 'artifactPath'),
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
                hash: any(named: 'hash'),
                canSideload: any(named: 'canSideload'),
                podfileLockHash: any(named: 'podfileLockHash'),
              ),
            ).thenThrow(
              const CodePushConflictException(message: 'already exists'),
            );
          });

          test('logs message and continues', () async {
            await runWithOverrides(
              () => codePushClientWrapper.createWindowsReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                projectRoot: projectRoot.path,
                releaseZipPath: releaseZip.path,
              ),
            );

            verify(
              () => logger.info(
                any(that: contains('already exists, continuing...')),
              ),
            ).called(1);
            verifyNever(() => progress.fail(any()));
          });
        });

        group('when createReleaseArtifact fails', () {
          setUp(() {
            when(
              () => codePushClient.createReleaseArtifact(
                artifactPath: any(named: 'artifactPath'),
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
                hash: any(named: 'hash'),
                canSideload: any(named: 'canSideload'),
                podfileLockHash: any(named: 'podfileLockHash'),
              ),
            ).thenThrow(Exception('something went wrong'));
          });

          test('exits with code 70', () async {
            await expectLater(
              () async => runWithOverrides(
                () => codePushClientWrapper.createWindowsReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  projectRoot: projectRoot.path,
                  releaseZipPath: releaseZip.path,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(() => progress.fail(any())).called(1);
          });
        });

        group('when createReleaseArtifact succeeds', () {
          setUp(() {
            when(
              () => codePushClient.createReleaseArtifact(
                artifactPath: any(named: 'artifactPath'),
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
                hash: any(named: 'hash'),
                canSideload: any(named: 'canSideload'),
                podfileLockHash: any(named: 'podfileLockHash'),
              ),
            ).thenAnswer((_) async {});
          });

          test('completes successfully', () async {
            await runWithOverrides(
              () async => codePushClientWrapper.createWindowsReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                projectRoot: projectRoot.path,
                releaseZipPath: releaseZip.path,
              ),
            );

            verify(() => progress.complete()).called(1);
            verifyNever(() => progress.fail(any()));
            verify(
              () => codePushClient.createReleaseArtifact(
                artifactPath: releaseZip.path,
                appId: appId,
                releaseId: releaseId,
                arch: primaryWindowsReleaseArtifactArch,
                platform: ReleasePlatform.windows,
                hash: any(named: 'hash'),
                canSideload: true,
                podfileLockHash: null,
              ),
            ).called(1);
          });
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

        void setUpProjectRoot({String? flavor}) {
          for (final arch in Arch.values) {
            final artifactPath = p.join(
              projectRoot.path,
              extractedAarPath,
              'jni',
              arch.androidBuildPath,
              'libapp.so',
            );
            File(artifactPath).createSync(recursive: true);
          }
          File(p.join(projectRoot.path, aarPath)).createSync(recursive: true);
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                    appId: app.appId,
                    releaseId: releaseId,
                    platform: releasePlatform,
                    aarPath: p.join(projectRoot.path, aarPath),
                    extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                    architectures: Arch.values,
                  ),
            ),
            exitsWithCode(ExitCode.software),
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                    appId: app.appId,
                    releaseId: releaseId,
                    platform: releasePlatform,
                    aarPath: p.join(projectRoot.path, aarPath),
                    extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                    architectures: Arch.values,
                  ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        });

        test(
          'logs message when uploading release artifact that already exists',
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
                podfileLockHash: any(named: 'podfileLockHash'),
              ),
            ).thenThrow(const CodePushConflictException(message: error));
            setUpProjectRoot();

            await runWithOverrides(
              () async =>
                  codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                    appId: app.appId,
                    releaseId: releaseId,
                    platform: releasePlatform,
                    aarPath: p.join(projectRoot.path, aarPath),
                    extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                    architectures: Arch.values,
                  ),
            );

            // 1 for each arch, 1 for the aab
            final numArtifactsUploaded = Arch.values.length + 1;
            verify(
              () => logger.info(any(that: contains('already exists'))),
            ).called(numArtifactsUploaded);
            verifyNever(() => progress.fail(error));
          },
        );

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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          setUpProjectRoot();

          await runWithOverrides(
            () async =>
                codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  aarPath: p.join(projectRoot.path, aarPath),
                  extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                  architectures: Arch.values,
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
          setUpProjectRoot();

          await runWithOverrides(
            () async =>
                codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  aarPath: p.join(projectRoot.path, aarPath),
                  extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                  architectures: Arch.values,
                ),
          );

          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('completes successfully when a flavor is provided', () async {
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
          setUpProjectRoot(flavor: flavorName);

          await runWithOverrides(
            () async =>
                codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  platform: releasePlatform,
                  aarPath: p.join(projectRoot.path, aarPath),
                  extractedAarDir: p.join(projectRoot.path, extractedAarPath),
                  architectures: Arch.values,
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
              podfileLockHash: null,
            ),
          ).called(Arch.values.length + 1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });
      });
    });

    group('createIosReleaseArtifacts', () {
      const podfileLockHash = 'podfile-lock-hash';
      final xcarchivePath = p.join('path', 'to', 'app.xcarchive');
      final runnerPath = p.join('path', 'to', 'runner.app');
      final releaseSupplementPath = p.join('path', 'to', 'supplement');

      void setUpProjectRoot({String? flavor}) {
        Directory(
          p.join(projectRoot.path, xcarchivePath),
        ).createSync(recursive: true);
        Directory(
          p.join(projectRoot.path, runnerPath),
        ).createSync(recursive: true);
        Directory(
          p.join(projectRoot.path, releaseSupplementPath),
        ).createSync(recursive: true);
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
            podfileLockHash: any(named: 'podfileLockHash'),
          ),
        ).thenAnswer((_) async {});
      });

      test(
        'exits with code 70 when xcarchive artifact creation fails',
        () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(
                named: 'artifactPath',
                that: endsWith('.xcarchive.zip'),
              ),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(projectRoot.path, xcarchivePath),
                runnerPath: p.join(projectRoot.path, runnerPath),
                isCodesigned: true,
                podfileLockHash: podfileLockHash,
                supplementPath: p.join(projectRoot.path, releaseSupplementPath),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        },
      );

      test(
        'exits with code 70 when uploading xcarchive that already exists',
        () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(
                named: 'artifactPath',
                that: endsWith('.xcarchive.zip'),
              ),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(const CodePushConflictException(message: error));
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(projectRoot.path, xcarchivePath),
                runnerPath: p.join(projectRoot.path, runnerPath),
                isCodesigned: false,
                podfileLockHash: podfileLockHash,
                supplementPath: p.join(projectRoot.path, releaseSupplementPath),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        },
      );

      test(
        'exits with code 70 when xcarchive artifact creation fails',
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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(projectRoot.path, xcarchivePath),
                runnerPath: p.join(projectRoot.path, runnerPath),
                isCodesigned: false,
                podfileLockHash: podfileLockHash,
                supplementPath: p.join(projectRoot.path, releaseSupplementPath),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        },
      );

      test(
        'exits with code 70 when supplement artifact creation fails',
        () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(
                named: 'artifactPath',
                that: endsWith('ios_supplement.zip'),
              ),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);
          setUpProjectRoot();

          await expectLater(
            () async => runWithOverrides(
              () async => codePushClientWrapper.createIosReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                xcarchivePath: p.join(projectRoot.path, xcarchivePath),
                runnerPath: p.join(projectRoot.path, runnerPath),
                isCodesigned: false,
                podfileLockHash: podfileLockHash,
                supplementPath: p.join(projectRoot.path, releaseSupplementPath),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        },
      );

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
            podfileLockHash: any(named: 'podfileLockHash'),
          ),
        ).thenAnswer((_) async {});
        setUpProjectRoot();

        await runWithOverrides(
          () async => codePushClientWrapper.createIosReleaseArtifacts(
            appId: app.appId,
            releaseId: releaseId,
            xcarchivePath: p.join(projectRoot.path, xcarchivePath),
            runnerPath: p.join(projectRoot.path, runnerPath),
            isCodesigned: true,
            podfileLockHash: podfileLockHash,
            supplementPath: p.join(projectRoot.path, releaseSupplementPath),
          ),
        );

        verify(() => progress.complete()).called(1);
        verifyNever(() => progress.fail(any()));
        verify(
          () => codePushClient.createReleaseArtifact(
            appId: app.appId,
            artifactPath: any(
              named: 'artifactPath',
              that: endsWith('.xcarchive.zip'),
            ),
            releaseId: releaseId,
            arch: any(named: 'arch'),
            platform: releasePlatform,
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
            podfileLockHash: podfileLockHash,
          ),
        ).called(1);
      });
    });

    group('createLinuxReleaseArtifacts', () {
      late Directory releaseBundle;

      setUp(() {
        releaseBundle = Directory(
          p.join(projectRoot.path, 'path', 'to', 'bundle'),
        )..createSync(recursive: true);
      });

      group('when createReleaseArtifact fails', () {
        setUp(() {
          when(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath'),
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(Exception('something went wrong'));
        });

        test('exits with code 70', () async {
          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createLinuxReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                bundle: releaseBundle,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any())).called(1);
        });
      });

      group('when createReleaseArtifact succeeds', () {
        setUp(() {
          when(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath'),
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenAnswer((_) async {});
        });

        test('completes successfully', () async {
          await runWithOverrides(
            () async => codePushClientWrapper.createLinuxReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              bundle: releaseBundle,
            ),
          );

          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
          verify(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath', that: endsWith('.zip')),
              appId: appId,
              releaseId: releaseId,
              arch: primaryLinuxReleaseArtifactArch,
              platform: ReleasePlatform.linux,
              hash: any(named: 'hash'),
              canSideload: true,
              podfileLockHash: null,
            ),
          ).called(1);
        });
      });
    });

    group('createMacosReleaseArtifacts', () {
      final appPath = p.join('path', 'to', 'Runner.app');
      final releaseSupplementPath = p.join('path', 'to', 'supplement');

      void setUpProjectRoot({String? flavor}) {
        Directory(
          p.join(projectRoot.path, appPath),
        ).createSync(recursive: true);
        Directory(
          p.join(projectRoot.path, releaseSupplementPath),
        ).createSync(recursive: true);
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
            podfileLockHash: any(named: 'podfileLockHash'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => ditto.archive(
            source: any(named: 'source'),
            destination: any(named: 'destination'),
          ),
        ).thenAnswer((invocation) async {
          final destination = invocation.namedArguments[#destination] as String;
          File(destination).createSync(recursive: true);
        });
        setUpProjectRoot();
      });

      test('exits with code 70 when creating app artifact fails', () async {
        when(
          () => codePushClient.createReleaseArtifact(
            artifactPath: any(named: 'artifactPath'),
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
            hash: any(named: 'hash'),
            canSideload: any(named: 'canSideload'),
            podfileLockHash: any(named: 'podfileLockHash'),
          ),
        ).thenThrow(Exception('oh no'));

        await expectLater(
          () async => runWithOverrides(
            () => codePushClientWrapper.createMacosReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              appPath: p.join(projectRoot.path, appPath),
              isCodesigned: false,
              podfileLockHash: null,
            ),
          ),
          exitsWithCode(ExitCode.software),
        );
      });

      test('completes successfully when release artifact is created', () async {
        await expectLater(
          runWithOverrides(
            () => codePushClientWrapper.createMacosReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              appPath: p.join(projectRoot.path, appPath),
              isCodesigned: false,
              podfileLockHash: null,
            ),
          ),
          completes,
        );
      });
    });

    group('createIosFrameworkReleaseArtifacts', () {
      final frameworkPath = p.join('path', 'to', 'App.xcframework');
      final releaseSupplementPath = p.join('path', 'to', 'supplement');

      void setUpProjectRoot({String? flavor}) {
        Directory(
          p.join(projectRoot.path, frameworkPath),
        ).createSync(recursive: true);
        Directory(
          p.join(projectRoot.path, releaseSupplementPath),
        ).createSync(recursive: true);
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
            podfileLockHash: any(named: 'podfileLockHash'),
          ),
        ).thenAnswer((_) async {});
        setUpProjectRoot();
      });

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
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(Exception('oh no'));

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
                appId: app.appId,
                releaseId: releaseId,
                appFrameworkPath: p.join(projectRoot.path, frameworkPath),
                supplementPath: null,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
        },
      );

      test(
        'exits with code 70 when supplement artifact creation fails',
        () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createReleaseArtifact(
              appId: any(named: 'appId'),
              artifactPath: any(
                named: 'artifactPath',
                that: endsWith('ios_framework_supplement.zip'),
              ),
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () async =>
                  codePushClientWrapper.createIosFrameworkReleaseArtifacts(
                    appId: app.appId,
                    releaseId: releaseId,
                    appFrameworkPath: p.join(projectRoot.path, frameworkPath),
                    supplementPath: p.join(
                      projectRoot.path,
                      releaseSupplementPath,
                    ),
                  ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(any(that: contains(error)))).called(1);
        },
      );

      test('completes successfully when release artifact is created', () async {
        await expectLater(
          runWithOverrides(
            () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
              appId: app.appId,
              releaseId: releaseId,
              appFrameworkPath: p.join(projectRoot.path, frameworkPath),
              supplementPath: null,
            ),
          ),
          completes,
        );
      });
    });

    group('updateReleaseStatus', () {
      test('exits with code 70 when updating release status fails', () async {
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
      });

      test('completes when updating release status succeeds', () async {
        when(
          () => codePushClient.updateReleaseStatus(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            status: any(named: 'status'),
          ),
        ).thenAnswer((_) async {});

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

      group('when metadata is provided', () {
        setUp(() {
          when(
            () => codePushClient.updateReleaseStatus(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
              status: any(named: 'status'),
              metadata: any(named: 'metadata'),
            ),
          ).thenAnswer((_) async {});
        });

        test('updates release status with metadata as json', () async {
          await runWithOverrides(
            () => codePushClientWrapper.updateReleaseStatus(
              appId: app.appId,
              releaseId: releaseId,
              platform: releasePlatform,
              status: ReleaseStatus.active,
              metadata: {'foo': 'bar'},
            ),
          );

          verify(
            () => codePushClient.updateReleaseStatus(
              appId: app.appId,
              releaseId: releaseId,
              platform: releasePlatform,
              status: ReleaseStatus.active,
              metadata: {'foo': 'bar'},
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });
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
              metadata: any(named: 'metadata'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createPatch(
                appId: appId,
                releaseId: releaseId,
                metadata: {'foo': 'bar'},
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
              metadata: any(named: 'metadata'),
            ),
          ).thenAnswer((_) async => patch);

          final result = await runWithOverrides(
            () => codePushClientWrapper.createPatch(
              appId: appId,
              releaseId: releaseId,
              metadata: {'foo': 'bar'},
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
        test('exits with code 70 when creating patch artifact fails', () async {
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
        });

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
              artifactPath: patchArtifactBundle.path,
              patchId: patchId,
              arch: arch.arch,
              platform: releasePlatform,
              hash: patchArtifactBundle.hash,
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
              metadata: any(named: 'metadata'),
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
              metadata: {'foo': 'bar'},
            ),
          );

          verify(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
              metadata: {'foo': 'bar'},
            ),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              appId: appId,
              artifactPath: patchArtifactBundle.path,
              patchId: patchId,
              arch: arch.arch,
              platform: releasePlatform,
              hash: patchArtifactBundle.hash,
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
              metadata: {'foo': 'bar'},
            ),
          );

          verify(
            () => codePushClient.createPatch(
              appId: appId,
              releaseId: releaseId,
              metadata: {'foo': 'bar'},
            ),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              appId: appId,
              artifactPath: patchArtifactBundle.path,
              patchId: patchId,
              arch: arch.arch,
              platform: releasePlatform,
              hash: patchArtifactBundle.hash,
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
              metadata: {'foo': 'bar'},
            ),
          );

          verify(
            () => logger.success(any(that: contains('Published Patch 2!'))),
          ).called(1);
        });
      });
    });

    group('getGCPDownloadSpeedTestUrl', () {
      final gcpSpeedTestUrl = Uri.parse('https://download.speedtest.gcp.com');

      setUp(() {
        when(
          () => codePushClient.getGCPDownloadSpeedTestUrl(),
        ).thenAnswer((_) async => gcpSpeedTestUrl);
      });

      test('calls codePushClient method', () async {
        await expectLater(
          runWithOverrides(
            () => codePushClientWrapper.getGCPDownloadSpeedTestUrl(),
          ),
          completion(gcpSpeedTestUrl),
        );

        verify(() => codePushClient.getGCPDownloadSpeedTestUrl()).called(1);
      });
    });

    group('getGCPUploadSpeedTestUrl', () {
      final gcpSpeedTestUrl = Uri.parse('https://upload.speedtest.gcp.com');

      setUp(() {
        when(
          () => codePushClient.getGCPUploadSpeedTestUrl(),
        ).thenAnswer((_) async => gcpSpeedTestUrl);
      });

      test('calls codePushClient method', () async {
        await expectLater(
          runWithOverrides(
            () => codePushClientWrapper.getGCPUploadSpeedTestUrl(),
          ),
          completion(gcpSpeedTestUrl),
        );

        verify(() => codePushClient.getGCPUploadSpeedTestUrl()).called(1);
      });
    });
  });
}
