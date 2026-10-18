import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
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
import 'helpers.dart';
import 'matchers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('scoped', () {
    late Auth auth;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
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
      platform = TestNativePlatform();
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
    late TestNativePlatform platform;
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
      platform = TestNativePlatform(
        script: Uri.file(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );
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
          when(
            () => logger.prompt(any(), hint: any(named: 'hint')),
          ).thenReturn(appName);
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

          verify(
            () => logger.prompt(any(), hint: any(named: 'hint')),
          ).called(1);
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

          verifyNever(() => logger.prompt(any(), hint: any(named: 'hint')));
          verify(
            () => codePushClient.createApp(
              displayName: appName,
              organizationId: organizationId,
            ),
          ).called(1);
        });
      });

      group('getCurrentUser', () {
        test('exits with code 70 when fetching the user fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getCurrentUser()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(codePushClientWrapper.getCurrentUser),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 when no current user is found', () async {
          when(
            () => codePushClient.getCurrentUser(),
          ).thenAnswer((_) async => null);

          await expectLater(
            () async => runWithOverrides(codePushClientWrapper.getCurrentUser),
            exitsWithCode(ExitCode.software),
          );
          verify(() => logger.err('Could not find current user.')).called(1);
        });

        test('returns the current user on success', () async {
          const expectedUser = PrivateUser(
            id: 1,
            email: 'user@example.com',
            jwtIssuer: 'https://accounts.google.com',
          );
          when(
            () => codePushClient.getCurrentUser(),
          ).thenAnswer((_) async => expectedUser);

          final user = await runWithOverrides(
            codePushClientWrapper.getCurrentUser,
          );

          expect(user, equals(expectedUser));
          verify(() => progress.complete()).called(1);
        });
      });

      group('getPlanLevel', () {
        test('exits with code 70 when getting the plan fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getPlanLevel()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(codePushClientWrapper.getPlanLevel),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns the plan level on success', () async {
          when(
            () => codePushClient.getPlanLevel(),
          ).thenAnswer((_) async => 'enterprise');

          final level = await runWithOverrides(
            codePushClientWrapper.getPlanLevel,
          );

          expect(level, equals('enterprise'));
          verify(() => progress.complete()).called(1);
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
              organization: organizationForTest(),
              role: Role.admin,
            ),
            OrganizationMembership(
              organization: organizationForTest(),
              role: Role.developer,
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

        test('reports the server error code and exits with an '
            'ApiErrorExit when the API call fails', () async {
          const error = CodePushException(
            message: 'Plan lacks this feature.',
            response: ErrorResponse(
              code: 'shorebird_plan_insufficient_tier',
              message: 'Plan lacks this feature.',
            ),
          );
          when(() => codePushClient.getApps()).thenThrow(error);

          await expectLater(
            () => runWithOverrides(codePushClientWrapper.getApps),
            throwsA(
              isA<ApiErrorExit>()
                  .having((e) => e.error, 'error', same(error))
                  .having(
                    (e) => e.exitCode,
                    'exitCode',
                    ExitCode.software.code,
                  ),
            ),
          );
          verify(() => progress.fail('$error')).called(1);
          verify(
            () => logger.info('Error code: shorebird_plan_insufficient_tier'),
          ).called(1);
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
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('exits with code 70 when app does not exist', () async {
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenAnswer((_) async => null);

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
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenAnswer((_) async => app);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getApp(appId: appId),
          );

          expect(result, app);
          verify(() => progress.complete()).called(1);
        });
      });

      group('maybeGetApp', () {
        test('requests the single app rather than the whole account', () async {
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenAnswer((_) async => app);

          await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          verify(() => codePushClient.getApp(appId: appId)).called(1);
          verifyNever(() => codePushClient.getApps());
        });

        test('exits with code 70 when fetching the app fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('succeeds if app does not exist', () async {
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenAnswer((_) async => null);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
          verifyNever(() => logger.err(any()));
        });

        test('returns null if the app belongs to someone else', () async {
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenThrow(CodePushForbiddenException(message: 'nope'));

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
          verifyNever(() => logger.err(any()));
        });

        test('returns app when app exists', () async {
          when(
            () => codePushClient.getApp(appId: any(named: 'appId')),
          ).thenAnswer((_) async => app);

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetApp(appId: appId),
          );

          expect(result, app);
          verify(() => progress.complete()).called(1);
        });
      });

      group('getReceivedInvitations', () {
        test('exits with code 70 when fetching invitations fails', () async {
          const error = 'something went wrong';
          when(() => codePushClient.getReceivedInvitations()).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              codePushClientWrapper.getReceivedInvitations,
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns the invitations', () async {
          final invitation = ReceivedInvitation(
            id: 'id',
            organizationId: 1,
            targetName: 'Acme',
            inviterEmail: 'admin@shorebird.dev',
            role: Role.developer,
            createdAt: DateTime.utc(2026, 4, 20),
            expiresAt: DateTime.utc(2026, 5, 4),
          );
          when(
            () => codePushClient.getReceivedInvitations(),
          ).thenAnswer((_) async => [invitation]);

          final invitations = await runWithOverrides(
            codePushClientWrapper.getReceivedInvitations,
          );

          expect(invitations, equals([invitation]));
          verify(() => progress.complete()).called(1);
        });
      });

      group('acceptInvitation', () {
        test('exits with code 70 when accepting fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.acceptInvitation(
              invitationId: any(named: 'invitationId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.acceptInvitation(invitationId: 'id'),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when the invitation is accepted', () async {
          when(
            () => codePushClient.acceptInvitation(invitationId: 'id'),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.acceptInvitation(invitationId: 'id'),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('declineInvitation', () {
        test('exits with code 70 when declining fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.declineInvitation(
              invitationId: any(named: 'invitationId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.declineInvitation(invitationId: 'id'),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when the invitation is declined', () async {
          when(
            () => codePushClient.declineInvitation(invitationId: 'id'),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.declineInvitation(invitationId: 'id'),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('account', () {
        test('updateCurrentUser sends the display name', () async {
          when(
            () => codePushClient.updateCurrentUser(
              displayName: any(named: 'displayName'),
            ),
          ).thenAnswer((_) async {});
          await runWithOverrides(
            () => codePushClientWrapper.updateCurrentUser(
              displayName: 'Jane Doe',
            ),
          );
          verify(
            () => codePushClient.updateCurrentUser(displayName: 'Jane Doe'),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });

        test('getEmailNotificationsEnabled returns the setting', () async {
          when(
            () => codePushClient.getEmailNotificationsEnabled(),
          ).thenAnswer((_) async => true);
          await expectLater(
            runWithOverrides(
              codePushClientWrapper.getEmailNotificationsEnabled,
            ),
            completion(isTrue),
          );
        });

        test('setEmailNotificationsEnabled sends the setting', () async {
          when(
            () => codePushClient.setEmailNotificationsEnabled(
              enabled: any(named: 'enabled'),
            ),
          ).thenAnswer((_) async {});
          await runWithOverrides(
            () => codePushClientWrapper.setEmailNotificationsEnabled(
              enabled: false,
            ),
          );
          verify(
            () => codePushClient.setEmailNotificationsEnabled(enabled: false),
          ).called(1);
        });
      });

      group('updateApp', () {
        test('exits with code 70 when renaming app fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.updateApp(
              appId: any(named: 'appId'),
              displayName: any(named: 'displayName'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.updateApp(
                appId: appId,
                displayName: displayName,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when app is successfully renamed', () async {
          when(
            () => codePushClient.updateApp(
              appId: appId,
              displayName: displayName,
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.updateApp(
              appId: appId,
              displayName: displayName,
            ),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('deleteApp', () {
        test('exits with code 70 when deleting app fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.deleteApp(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.deleteApp(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when app is successfully deleted', () async {
          when(
            () => codePushClient.deleteApp(appId: appId),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.deleteApp(appId: appId),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('deleteRelease', () {
        const releaseId = 42;

        test('exits with code 70 when deleting the release fails', () async {
          final error = CodePushForbiddenException(message: 'Forbidden');
          when(
            () => codePushClient.deleteRelease(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.deleteRelease(
                appId: appId,
                releaseId: releaseId,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail('$error')).called(1);
        });

        test('completes when the release is successfully deleted', () async {
          when(
            () => codePushClient.deleteRelease(
              appId: appId,
              releaseId: releaseId,
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.deleteRelease(
              appId: appId,
              releaseId: releaseId,
            ),
          );

          verify(() => progress.complete()).called(1);
        });
      });

      group('deleteReleaseArtifacts', () {
        const releaseId = 42;

        test('exits with code 70 when deleting artifacts fails', () async {
          final error = CodePushForbiddenException(message: 'Forbidden');
          when(
            () => codePushClient.deleteReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.deleteReleaseArtifacts(
                appId: appId,
                releaseId: releaseId,
                platform: ReleasePlatform.ios,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail('$error')).called(1);
        });

        test('completes when the artifacts are successfully deleted', () async {
          when(
            () => codePushClient.deleteReleaseArtifacts(
              appId: appId,
              releaseId: releaseId,
              platform: ReleasePlatform.ios,
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.deleteReleaseArtifacts(
              appId: appId,
              releaseId: releaseId,
              platform: ReleasePlatform.ios,
            ),
          );

          verify(
            () => logger.progress('Deleting ios release artifacts'),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });
      });

      group('transferApp', () {
        test('exits with code 70 when transferring app fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.transferApp(
              organizationId: any(named: 'organizationId'),
              appId: any(named: 'appId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.transferApp(
                organizationId: organizationId,
                appId: appId,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when app is successfully transferred', () async {
          when(
            () => codePushClient.transferApp(
              organizationId: organizationId,
              appId: appId,
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.transferApp(
              organizationId: organizationId,
              appId: appId,
            ),
          );

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

      group('getChannels', () {
        test('exits with code 70 when fetching channels fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getChannels(appId: appId),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns channels when channels are fetched', () async {
          when(
            () => codePushClient.getChannels(appId: appId),
          ).thenAnswer((_) async => [channel]);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getChannels(appId: appId),
          );

          expect(result, [channel]);
          verify(() => progress.complete()).called(1);
        });
      });

      group('deleteChannel', () {
        test('exits with code 70 when deleting channel fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.deleteChannel(
              appId: any(named: 'appId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.deleteChannel(
                appId: appId,
                channelId: channel.id,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes when channel is successfully deleted', () async {
          when(
            () => codePushClient.deleteChannel(
              appId: appId,
              channelId: channel.id,
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.deleteChannel(
              appId: appId,
              channelId: channel.id,
            ),
          );

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

      group('prepareAndroidReleaseArtifacts', () {
        final aabPath = p.join('path', 'to', 'app.aab');

        String libappPath(Arch arch, {String? flavor}) => p.join(
          projectRoot.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          flavor != null ? '${flavor}Release' : 'release',
          'out',
          'lib',
          arch.androidBuildPath,
          'libapp.so',
        );

        void setUpProjectRoot({String? flavor}) {
          File(p.join(projectRoot.path, aabPath)).createSync(recursive: true);
          for (final arch in Arch.values) {
            File(libappPath(arch, flavor: flavor)).createSync(recursive: true);
          }
        }

        Future<List<ReleaseArtifactUpload>> prepare({
          String? aab,
          String? flavor,
        }) => runWithOverrides(
          () => codePushClientWrapper.prepareAndroidReleaseArtifacts(
            platform: ReleasePlatform.android,
            projectRoot: projectRoot.path,
            aabPath: aab ?? p.join(projectRoot.path, aabPath),
            architectures: Arch.values,
            flavor: flavor,
          ),
        );

        test('exits with code 70 when artifacts cannot be found', () async {
          await expectLater(prepare, exitsWithCode(ExitCode.software));

          verify(
            () => progress.fail(
              any(that: contains('Cannot find release build artifacts')),
            ),
          ).called(1);
        });

        test('returns the libapp.so of each arch and the aab', () async {
          setUpProjectRoot();

          final artifacts = await prepare();

          expect(
            artifacts,
            equals([
              for (final arch in Arch.values)
                ReleaseArtifactUpload(
                  file: File(libappPath(arch)),
                  name: arch.arch,
                  arch: arch.arch,
                  platform: ReleasePlatform.android,
                  canSideload: false,
                ),
              ReleaseArtifactUpload(
                file: File(p.join(projectRoot.path, aabPath)),
                name: 'aab',
                arch: 'aab',
                platform: ReleasePlatform.android,
                canSideload: true,
              ),
            ]),
          );
          verify(() => logger.progress('Preparing artifacts')).called(1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
          verifyNever(
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
          );
        });

        test('looks in the flavor build directory when a flavor is '
            'provided', () async {
          const flavorName = 'myFlavor';
          setUpProjectRoot(flavor: flavorName);

          final artifacts = await prepare(flavor: flavorName);

          expect(
            artifacts.take(Arch.values.length).map((a) => a.file.path),
            equals([
              for (final arch in Arch.values)
                libappPath(arch, flavor: flavorName),
            ]),
          );
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test(
          'skips arches whose libapp.so is missing (abiFilters case)',
          () async {
            setUpProjectRoot();
            // Simulate AGP filtering: remove armeabi-v7a libapp.so to mirror
            // a project with ndk.abiFilters that excludes arm32.
            const missingArch = Arch.arm32;
            File(libappPath(missingArch)).deleteSync();

            final artifacts = await prepare();

            // One artifact per surviving arch, plus one for the aab.
            expect(artifacts, hasLength(Arch.values.length - 1 + 1));
            expect(
              artifacts.map((a) => a.arch),
              isNot(contains(missingArch.arch)),
            );
            verify(() => progress.complete()).called(1);
            verifyNever(() => progress.fail(any()));
          },
        );

        test(
          'exits with code 70 when every requested arch is missing',
          () async {
            // Create the archs directory but no libapp.so files inside it.
            // This mirrors AGP producing an empty strip output (all archs
            // filtered out).
            for (final arch in Arch.values) {
              File(libappPath(arch)).parent.createSync(recursive: true);
            }
            File(p.join(projectRoot.path, aabPath)).createSync(recursive: true);

            await expectLater(prepare, exitsWithCode(ExitCode.software));

            verify(
              () => progress.fail(
                any(
                  that: contains('No architecture artifacts found to upload'),
                ),
              ),
            ).called(1);
            verifyNever(() => progress.complete());
          },
        );

        test(
          'extracts libapp.so from the aab when the strip output is empty',
          () async {
            // The strip output dirs exist but contain no libapp.so, as happens
            // when AGP's strip task emits nothing on Flutter 3.44+. The
            // libraries still ship inside the aab, which is read first, so
            // preparing succeeds regardless of the strip output.
            for (final arch in Arch.values) {
              File(libappPath(arch)).parent.createSync(recursive: true);
            }
            // A real aab containing base/lib/<arch>/libapp.so for three arches.
            final aab = File(
              p.join(fixturesDirectory, 'aabs', 'changed_asset.aab'),
            );

            final artifacts = await prepare(aab: aab.path);

            // Each per-arch artifact comes from the directory the aab was
            // extracted into, not from the empty strip output.
            final archArtifacts = artifacts.where((a) => a.arch != 'aab');
            expect(archArtifacts, hasLength(3));
            for (final artifact in archArtifacts) {
              expect(artifact.file.path, contains('shorebird_aab_libapps'));
              expect(artifact.file.existsSync(), isTrue);
            }
            expect(artifacts.last.file.path, equals(aab.path));
            verify(() => progress.complete()).called(1);
            verifyNever(() => progress.fail(any()));
          },
        );

        test(
          'fails with an accurate message when the aab has no libapp.so',
          () async {
            // A real aab that packages a native lib but no libapp.so, as
            // happens when a custom Gradle build drops the Dart library before
            // bundling (https://github.com/shorebirdtech/shorebird/issues/3813).
            final archive = Archive()
              ..addFile(
                ArchiveFile.string('base/lib/arm64-v8a/libflutter.so', 'so'),
              );
            final aab = File(p.join(projectRoot.path, 'no_libapp.aab'))
              ..createSync(recursive: true)
              ..writeAsBytesSync(ZipEncoder().encode(archive));

            await expectLater(
              () => prepare(aab: aab.path),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => progress.fail(
                any(
                  that: contains(
                    'does not contain libapp.so for any architecture',
                  ),
                ),
              ),
            ).called(1);
          },
        );
      });

      group('prepareAndroidArchiveReleaseArtifacts', () {
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

        String libappPath(Arch arch) => p.join(
          projectRoot.path,
          extractedAarPath,
          'jni',
          arch.androidBuildPath,
          'libapp.so',
        );

        void setUpProjectRoot() {
          for (final arch in Arch.values) {
            File(libappPath(arch)).createSync(recursive: true);
          }
          File(p.join(projectRoot.path, aarPath)).createSync(recursive: true);
        }

        List<ReleaseArtifactUpload> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareAndroidArchiveReleaseArtifacts(
            platform: ReleasePlatform.android,
            aarPath: p.join(projectRoot.path, aarPath),
            extractedAarDir: p.join(projectRoot.path, extractedAarPath),
            architectures: Arch.values,
          ),
        );

        test('returns the libapp.so of each arch and the aar', () {
          setUpProjectRoot();

          final artifacts = prepare();

          expect(
            artifacts,
            equals([
              for (final arch in Arch.values)
                ReleaseArtifactUpload(
                  file: File(libappPath(arch)),
                  name: arch.arch,
                  arch: arch.arch,
                  platform: ReleasePlatform.android,
                  canSideload: false,
                ),
              ReleaseArtifactUpload(
                file: File(p.join(projectRoot.path, aarPath)),
                name: 'aar',
                arch: 'aar',
                platform: ReleasePlatform.android,
                canSideload: false,
              ),
            ]),
          );
          verify(() => logger.progress('Preparing artifacts')).called(1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('skips archs with no libapp.so and returns the rest', () {
          setUpProjectRoot();
          const missingArch = Arch.x86_64;
          File(libappPath(missingArch)).deleteSync();

          final artifacts = prepare();

          // One artifact per surviving arch, plus one for the aar.
          expect(artifacts, hasLength(Arch.values.length));
          expect(
            artifacts.map((a) => a.arch),
            isNot(contains(missingArch.arch)),
          );
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('exits with code 70 when every requested arch is missing', () {
          File(p.join(projectRoot.path, aarPath)).createSync(recursive: true);
          final jniDir = p.join(projectRoot.path, extractedAarPath, 'jni');

          expect(prepare, exitsWithCode(ExitCode.software));

          verify(
            () => progress.fail(
              any(
                that: allOf(
                  contains('No architecture artifacts found to upload'),
                  contains('under $jniDir '),
                ),
              ),
            ),
          ).called(1);
          verifyNever(() => progress.complete());
        });
      });

      group('prepareWindowsReleaseArtifacts', () {
        late Directory releaseDirectory;
        late Directory stagingDirectory;

        setUp(() {
          releaseDirectory = Directory(
            p.join(projectRoot.path, 'path', 'to', 'Release'),
          )..createSync(recursive: true);
          File(
            p.join(releaseDirectory.path, 'app.exe'),
          ).writeAsStringSync('exe');
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<List<ReleaseArtifactUpload>> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareWindowsReleaseArtifacts(
            releaseDirectory: releaseDirectory,
            stagingDirectory: stagingDirectory,
          ),
        );

        test('returns the release directory zipped into staging', () async {
          final artifacts = await prepare();

          final zip = File(p.join(stagingDirectory.path, 'Release.zip'));
          expect(
            artifacts,
            equals([
              ReleaseArtifactUpload(
                file: zip,
                name: 'Windows release (exe)',
                arch: primaryWindowsReleaseArtifactArch,
                platform: ReleasePlatform.windows,
                canSideload: true,
              ),
            ]),
          );
          expect(zip.existsSync(), isTrue);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('writes nothing outside the staging directory', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });
      });

      group('prepareIosReleaseArtifacts', () {
        const podfileLockHash = 'podfile-lock-hash';
        final xcarchivePath = p.join('path', 'to', 'app.xcarchive');
        final runnerPath = p.join('path', 'to', 'runner.app');

        late Directory stagingDirectory;

        setUp(() {
          Directory(
            p.join(projectRoot.path, xcarchivePath),
          ).createSync(recursive: true);
          Directory(
            p.join(projectRoot.path, runnerPath),
          ).createSync(recursive: true);
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<List<ReleaseArtifactUpload>> prepare({
          bool isCodesigned = true,
        }) => runWithOverrides(
          () => codePushClientWrapper.prepareIosReleaseArtifacts(
            xcarchivePath: p.join(projectRoot.path, xcarchivePath),
            runnerPath: p.join(projectRoot.path, runnerPath),
            isCodesigned: isCodesigned,
            podfileLockHash: podfileLockHash,
            stagingDirectory: stagingDirectory,
          ),
        );

        test('returns the xcarchive and runner zipped into staging', () async {
          final artifacts = await prepare();

          expect(
            artifacts,
            equals([
              ReleaseArtifactUpload(
                file: File(p.join(stagingDirectory.path, 'app.xcarchive.zip')),
                name: 'xcarchive',
                arch: 'xcarchive',
                platform: ReleasePlatform.ios,
                canSideload: false,
                podfileLockHash: podfileLockHash,
              ),
              ReleaseArtifactUpload(
                file: File(p.join(stagingDirectory.path, 'runner.app.zip')),
                name: 'runner.app',
                arch: 'runner',
                platform: ReleasePlatform.ios,
                canSideload: true,
                podfileLockHash: podfileLockHash,
              ),
            ]),
          );
          for (final artifact in artifacts) {
            expect(artifact.file.existsSync(), isTrue);
          }
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('removes .dylib files from the zipped xcarchive', () async {
          File(
            p.join(projectRoot.path, xcarchivePath, 'Info.plist'),
          ).writeAsStringSync('plist');
          File(
              p.join(projectRoot.path, xcarchivePath, 'Products', 'a.dylib'),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('dylib');

          final artifacts = await prepare();

          final archive = ZipDecoder().decodeBytes(
            artifacts.first.file.readAsBytesSync(),
          );
          final names = archive.files.map((f) => f.name);
          expect(names, contains(endsWith('Info.plist')));
          expect(names, isNot(contains(endsWith('.dylib'))));
          // The original xcarchive is left alone.
          expect(
            File(
              p.join(projectRoot.path, xcarchivePath, 'Products', 'a.dylib'),
            ).existsSync(),
            isTrue,
          );
        });

        test('deletes the thinned archive it creates', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });

        test(
          'marks the runner as not sideloadable when not codesigned',
          () async {
            final artifacts = await prepare(isCodesigned: false);

            final runner = artifacts.singleWhere((a) => a.arch == 'runner');
            expect(runner.canSideload, isFalse);
          },
        );
      });

      group('prepareLinuxReleaseArtifacts', () {
        late Directory releaseBundle;
        late Directory stagingDirectory;

        setUp(() {
          releaseBundle = Directory(
            p.join(projectRoot.path, 'path', 'to', 'bundle'),
          )..createSync(recursive: true);
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<List<ReleaseArtifactUpload>> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareLinuxReleaseArtifacts(
            bundle: releaseBundle,
            stagingDirectory: stagingDirectory,
          ),
        );

        test('returns the bundle zipped into staging', () async {
          final artifacts = await prepare();

          final zip = File(p.join(stagingDirectory.path, 'bundle.zip'));
          expect(
            artifacts,
            equals([
              ReleaseArtifactUpload(
                file: zip,
                name: 'bundle',
                arch: primaryLinuxReleaseArtifactArch,
                platform: ReleasePlatform.linux,
                canSideload: true,
              ),
            ]),
          );
          expect(zip.existsSync(), isTrue);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('writes nothing outside the staging directory', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });
      });

      group('prepareMacosReleaseArtifacts', () {
        final appPath = p.join('path', 'to', 'Runner.app');

        late Directory stagingDirectory;

        setUp(() {
          when(
            () => ditto.archive(
              source: any(named: 'source'),
              destination: any(named: 'destination'),
            ),
          ).thenAnswer((invocation) async {
            final destination =
                invocation.namedArguments[#destination] as String;
            File(destination).createSync(recursive: true);
          });
          Directory(
            p.join(projectRoot.path, appPath),
          ).createSync(recursive: true);
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<List<ReleaseArtifactUpload>> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareMacosReleaseArtifacts(
            appPath: p.join(projectRoot.path, appPath),
            podfileLockHash: 'podfile-lock-hash',
            stagingDirectory: stagingDirectory,
          ),
        );

        test('returns the app archived into staging', () async {
          final artifacts = await prepare();

          final zip = File(p.join(stagingDirectory.path, 'Runner.app.zip'));
          expect(
            artifacts,
            equals([
              ReleaseArtifactUpload(
                file: zip,
                name: 'app',
                arch: 'app',
                platform: ReleasePlatform.macos,
                canSideload: true,
                podfileLockHash: 'podfile-lock-hash',
              ),
            ]),
          );
          verify(
            () => ditto.archive(
              source: p.join(projectRoot.path, appPath),
              destination: zip.path,
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('writes nothing outside the staging directory', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });
      });

      group('prepareIosFrameworkReleaseArtifacts', () {
        final frameworkPath = p.join('path', 'to', 'App.xcframework');

        late Directory stagingDirectory;

        setUp(() {
          Directory(
            p.join(projectRoot.path, frameworkPath),
          ).createSync(recursive: true);
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<List<ReleaseArtifactUpload>> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareIosFrameworkReleaseArtifacts(
            appFrameworkPath: p.join(projectRoot.path, frameworkPath),
            stagingDirectory: stagingDirectory,
          ),
        );

        test('returns the xcframework zipped into staging', () async {
          final artifacts = await prepare();

          final zip = File(
            p.join(stagingDirectory.path, 'App.xcframework.zip'),
          );
          expect(
            artifacts,
            equals([
              ReleaseArtifactUpload(
                file: zip,
                name: 'xcframework',
                arch: 'xcframework',
                platform: ReleasePlatform.ios,
                canSideload: false,
              ),
            ]),
          );
          expect(zip.existsSync(), isTrue);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('writes nothing outside the staging directory', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });
      });

      group('prepareSupplementReleaseArtifact', () {
        late Directory supplementDirectory;
        late Directory stagingDirectory;

        setUp(() {
          supplementDirectory = Directory(
            p.join(projectRoot.path, 'path', 'to', 'supplement'),
          )..createSync(recursive: true);
          stagingDirectory = Directory.systemTemp.createTempSync();
        });

        Future<ReleaseArtifactUpload> prepare() => runWithOverrides(
          () => codePushClientWrapper.prepareSupplementReleaseArtifact(
            platform: ReleasePlatform.ios,
            supplementDirectoryPath: supplementDirectory.path,
            arch: 'ios_supplement',
            stagingDirectory: stagingDirectory,
          ),
        );

        test(
          'returns the supplement zipped into staging as its arch',
          () async {
            final artifact = await prepare();

            final zip = File(
              p.join(stagingDirectory.path, 'ios_supplement.zip'),
            );
            expect(
              artifact,
              equals(
                ReleaseArtifactUpload(
                  file: zip,
                  name: 'supplement',
                  arch: 'ios_supplement',
                  platform: ReleasePlatform.ios,
                  canSideload: false,
                ),
              ),
            );
            expect(zip.existsSync(), isTrue);
          },
        );

        test('writes nothing outside the staging directory', () async {
          final systemTemp = createSystemTemp();
          await runWithSystemTemp(systemTemp, prepare);

          expect(systemTemp.listSync(), isEmpty);
        });
      });

      group('uploadReleaseArtifacts', () {
        late File firstFile;
        late File secondFile;
        late List<ReleaseArtifactUpload> artifacts;

        setUp(() {
          final dir = Directory.systemTemp.createTempSync();
          firstFile = File(p.join(dir.path, 'runner.app.zip'))
            ..writeAsStringSync('runner');
          secondFile = File(p.join(dir.path, 'supplement.zip'))
            ..writeAsStringSync('supplement');
          artifacts = [
            ReleaseArtifactUpload(
              file: firstFile,
              name: 'runner.app',
              arch: 'runner',
              platform: ReleasePlatform.ios,
              canSideload: true,
              podfileLockHash: 'podfile-lock-hash',
            ),
            ReleaseArtifactUpload(
              file: secondFile,
              name: 'supplement',
              arch: 'ios_supplement',
              platform: ReleasePlatform.ios,
              canSideload: false,
            ),
          ];
        });

        Future<void> upload({String? message}) => runWithOverrides(
          () => message == null
              ? codePushClientWrapper.uploadReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  artifacts: artifacts,
                )
              : codePushClientWrapper.uploadReleaseArtifacts(
                  appId: app.appId,
                  releaseId: releaseId,
                  artifacts: artifacts,
                  message: message,
                ),
        );

        void stubCreateReleaseArtifact(Object? error, {String? arch}) {
          final stub = when(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath'),
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: arch ?? any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          );
          if (error == null) {
            stub.thenAnswer((_) async {});
          } else {
            stub.thenThrow(error);
          }
        }

        setUp(() => stubCreateReleaseArtifact(null));

        test('uploads each artifact with what it says about itself', () async {
          await upload();

          verify(() => logger.progress('Uploading artifacts')).called(1);
          verify(
            () => codePushClient.createReleaseArtifact(
              appId: app.appId,
              artifactPath: firstFile.path,
              releaseId: releaseId,
              arch: 'runner',
              platform: ReleasePlatform.ios,
              hash: '${sha256.convert(utf8.encode('runner'))}',
              canSideload: true,
              podfileLockHash: 'podfile-lock-hash',
            ),
          ).called(1);
          verify(
            () => codePushClient.createReleaseArtifact(
              appId: app.appId,
              artifactPath: secondFile.path,
              releaseId: releaseId,
              arch: 'ios_supplement',
              platform: ReleasePlatform.ios,
              hash: '${sha256.convert(utf8.encode('supplement'))}',
              canSideload: false,
              podfileLockHash: null,
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('shows the given message while uploading', () async {
          await upload(message: 'Uploading supplement artifacts');

          verify(
            () => logger.progress('Uploading supplement artifacts'),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });

        test('completes without uploading when given no artifacts', () async {
          artifacts = [];

          await upload();

          verifyNever(
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
          );
          verify(() => progress.complete()).called(1);
        });

        test('logs and continues when an artifact already exists', () async {
          stubCreateReleaseArtifact(
            const CodePushConflictException(message: 'exists'),
            arch: 'runner',
          );

          await upload();

          verify(
            () => logger.info(
              any(
                that: contains(
                  'runner.app artifact already exists, continuing',
                ),
              ),
            ),
          ).called(1);
          verify(
            () => codePushClient.createReleaseArtifact(
              artifactPath: secondFile.path,
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: 'ios_supplement',
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('logs once per artifact that already exists', () async {
          stubCreateReleaseArtifact(
            const CodePushConflictException(message: 'exists'),
          );

          await upload();

          verify(
            () => logger.info(any(that: contains('already exists'))),
          ).called(artifacts.length);
          verify(() => progress.complete()).called(1);
          verifyNever(() => progress.fail(any()));
        });

        test('exits with code 70 when uploading an artifact fails', () async {
          stubCreateReleaseArtifact(Exception('oh no'), arch: 'runner');

          await expectLater(upload, exitsWithCode(ExitCode.software));

          verify(
            () => progress.fail(
              'Error uploading runner.app artifact: Exception: oh no',
            ),
          ).called(1);
          verifyNever(() => progress.complete());
          // The remaining artifacts are not uploaded.
          verifyNever(
            () => codePushClient.createReleaseArtifact(
              artifactPath: any(named: 'artifactPath'),
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              arch: 'ios_supplement',
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
              canSideload: any(named: 'canSideload'),
              podfileLockHash: any(named: 'podfileLockHash'),
            ),
          );
        });

        test(
          'exits with code 70 when storage rejects an upload with a 409',
          () async {
            stubCreateReleaseArtifact(
              const CodePushUploadException(
                message: 'Failed to upload artifact (Conflict 409)',
                statusCode: HttpStatus.conflict,
              ),
            );

            await expectLater(upload, exitsWithCode(ExitCode.software));

            verifyNever(
              () => logger.info(any(that: contains('already exists'))),
            );
            verify(
              () => progress.fail(
                any(that: startsWith('Error uploading runner.app artifact')),
              ),
            ).called(1);
          },
        );

        test('tells the user to upgrade when the server requires it', () async {
          stubCreateReleaseArtifact(
            const CodePushUpgradeRequiredException(message: 'upgrade'),
          );

          await expectLater(upload, exitsWithCode(ExitCode.software));

          verify(() => progress.fail()).called(1);
          verify(
            () => logger.err('Your version of shorebird is out of date.'),
          ).called(1);
          verifyNever(() => progress.complete());
        });
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

      group('rollbackPatch', () {
        const releaseId = 7;
        const patchNumber = 1;

        test('exits with code 70 when rollback fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.rollbackPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.rollbackPatch(
                appId: appId,
                releaseId: releaseId,
                patchId: patchId,
                patchNumber: patchNumber,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes progress when patch is rolled back', () async {
          when(
            () => codePushClient.rollbackPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenAnswer((_) async => true);

          final changed = await runWithOverrides(
            () => codePushClientWrapper.rollbackPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
              patchNumber: patchNumber,
            ),
          );

          expect(changed, isTrue);
          verify(() => progress.complete()).called(1);
        });

        test('forwards the no-op result from the client', () async {
          when(
            () => codePushClient.rollbackPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenAnswer((_) async => false);

          final changed = await runWithOverrides(
            () => codePushClientWrapper.rollbackPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
              patchNumber: patchNumber,
            ),
          );

          expect(changed, isFalse);
          verify(
            () => progress.complete(
              'No change: patch $patchNumber was already rolled back',
            ),
          ).called(1);
        });

        test(
          'omits patch number from progress label when not provided',
          () async {
            when(
              () => codePushClient.rollbackPatch(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                patchId: any(named: 'patchId'),
              ),
            ).thenAnswer((_) async => true);

            await runWithOverrides(
              () => codePushClientWrapper.rollbackPatch(
                appId: appId,
                releaseId: releaseId,
                patchId: patchId,
              ),
            );

            verify(() => logger.progress('Rolling back patch')).called(1);
          },
        );
      });

      group('rollforwardPatch', () {
        const releaseId = 7;
        const patchNumber = 1;

        test('exits with code 70 when rollforward fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.rollforwardPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.rollforwardPatch(
                appId: appId,
                releaseId: releaseId,
                patchId: patchId,
                patchNumber: patchNumber,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('completes progress when patch is rolled forward', () async {
          when(
            () => codePushClient.rollforwardPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenAnswer((_) async => true);

          final changed = await runWithOverrides(
            () => codePushClientWrapper.rollforwardPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
              patchNumber: patchNumber,
            ),
          );

          expect(changed, isTrue);
          verify(() => progress.complete()).called(1);
        });

        test('forwards the no-op result from the client', () async {
          when(
            () => codePushClient.rollforwardPatch(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
            ),
          ).thenAnswer((_) async => false);

          final changed = await runWithOverrides(
            () => codePushClientWrapper.rollforwardPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
              patchNumber: patchNumber,
            ),
          );

          expect(changed, isFalse);
          verify(
            () => progress.complete(
              'No change: patch $patchNumber was already active',
            ),
          ).called(1);
        });

        test(
          'omits patch number from progress label when not provided',
          () async {
            when(
              () => codePushClient.rollforwardPatch(
                appId: any(named: 'appId'),
                releaseId: any(named: 'releaseId'),
                patchId: any(named: 'patchId'),
              ),
            ).thenAnswer((_) async => true);

            await runWithOverrides(
              () => codePushClientWrapper.rollforwardPatch(
                appId: appId,
                releaseId: releaseId,
                patchId: patchId,
              ),
            );

            verify(() => logger.progress('Rolling forward patch')).called(1);
          },
        );
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
