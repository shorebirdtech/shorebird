import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group(CodePushClientWrapper, () {
    Matcher exitsWithCode(ExitCode exitcode) => throwsA(
          isA<ProcessExit>().having(
            (e) => e.exitCode,
            'exitCode',
            exitcode.code,
          ),
        );
    const appId = 'test-app-id';
    const app = AppMetadata(appId: appId, displayName: 'Test App');
    const channelName = 'my-channel';
    const channel = Channel(id: 0, appId: appId, name: channelName);
    const patchId = 1;
    const patchNumber = 2;
    const patch = Patch(id: patchId, number: patchNumber);
    const platform = 'ios';
    const releaseId = 123;
    const arch = Arch.arm64;
    const flutterRevision = '123';
    const displayName = 'TestApp';
    const releaseVersion = '1.0.0';
    const release = Release(
      id: 1,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      displayName: displayName,
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
      )
    };
    const releaseArtifact = ReleaseArtifact(
      id: 1,
      releaseId: releaseId,
      arch: 'aarch64',
      platform: platform,
      hash: 'asdf',
      size: 4,
      url: 'url',
    );

    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late CodePushClientWrapper codePushClientWrapper;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUpAll(setExitFunctionForTests);

    tearDownAll(restoreExitFunction);

    setUp(() {
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();

      codePushClientWrapper = runWithOverrides(
        () => CodePushClientWrapper(codePushClient: codePushClient),
      );

      when(() => logger.progress(any())).thenReturn(progress);
    });

    group('app', () {
      group('getApp', () {
        test('throws error when fetching apps fails.', () async {
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

        test('throws error when app does not exist', () async {
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
        test('throws error when fetching apps fails.', () async {
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
        test('throws error when fetching channels fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getChannels(appId: any(named: 'appId')),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetChannel(
                appId: appId,
                name: channelName,
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
              name: channelName,
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
              name: channelName,
            ),
          );

          expect(result, channel);
          verify(() => progress.complete()).called(1);
        });
      });

      group('createChannel', () {
        test('throws error when creating channel fails.', () async {
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
                name: channelName,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns channel when channel is successfully created.', () async {
          when(
            () => codePushClient.createChannel(
              appId: appId,
              channel: channelName,
            ),
          ).thenAnswer((_) async => channel);

          final result = await runWithOverrides(
            () => codePushClientWrapper.createChannel(
              appId: appId,
              name: channelName,
            ),
          );

          expect(result, channel);
          verify(() => progress.complete()).called(1);
        });
      });
    });

    group('release', () {
      group('getRelease', () {
        test('throws error when fetching release fails.', () async {
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

        test('throws error when release does not exist', () async {
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
        test('throws error when fetching apps fails.', () async {
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
    });

    group('release artifact', () {
      group('getReleaseArtifacts', () {
        test('exits with code 70 if fetching release artifact fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleaseArtifact(
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.getReleaseArtifacts(
                releaseId: releaseId,
                architectures: archMap,
                platform: platform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns release artifacts when release artifacts exist',
            () async {
          when(
            () => codePushClient.getReleaseArtifact(
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenAnswer((_) async => releaseArtifact);

          final result = await runWithOverrides(
            () => codePushClientWrapper.getReleaseArtifacts(
              releaseId: releaseId,
              architectures: archMap,
              platform: platform,
            ),
          );

          expect(result, {arch: releaseArtifact});
          verify(() => progress.complete()).called(1);
        });
      });

      group('maybeGetReleaseArtifact', () {
        test('exits with code 70 if fetching release artifact fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.getReleaseArtifact(
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.maybeGetReleaseArtifact(
                releaseId: releaseId,
                arch: arch.name,
                platform: platform,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );

          verify(() => progress.fail(error)).called(1);
        });

        test('returns null if release artifact does not exist', () async {
          when(
            () => codePushClient.getReleaseArtifact(
              releaseId: any(named: 'releaseId'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
            ),
          ).thenThrow(CodePushNotFoundException(message: 'not found'));

          final result = await runWithOverrides(
            () => codePushClientWrapper.maybeGetReleaseArtifact(
              releaseId: releaseId,
              arch: arch.name,
              platform: platform,
            ),
          );

          expect(result, isNull);
          verify(() => progress.complete()).called(1);
        });

        test(
          'returns release artifact if release artifact exists',
          () async {
            when(
              () => codePushClient.getReleaseArtifact(
                releaseId: any(named: 'releaseId'),
                arch: any(named: 'arch'),
                platform: any(named: 'platform'),
              ),
            ).thenAnswer((_) async => releaseArtifact);

            final result = await runWithOverrides(
              () => codePushClientWrapper.maybeGetReleaseArtifact(
                releaseId: releaseId,
                arch: arch.name,
                platform: platform,
              ),
            );

            expect(result, releaseArtifact);
            verify(() => progress.complete()).called(1);
          },
        );
      });
    });

    group('patch', () {
      group('createPatch', () {
        test('exits with code 70 when creating patch fails', () async {
          const error = 'something went wrong';
          when(
            () => codePushClient.createPatch(releaseId: releaseId),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.createPatch(
                releaseId: releaseId,
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail(error)).called(1);
        });

        test('returns patch when patch is successfully created.', () async {
          when(
            () => codePushClient.createPatch(releaseId: releaseId),
          ).thenAnswer((_) async => patch);

          final result = await runWithOverrides(
            () => codePushClientWrapper.createPatch(
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
              patchId: any(named: 'patchId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenThrow(error);

          await expectLater(
            () async => runWithOverrides(
              () => codePushClientWrapper.promotePatch(
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
              patchId: any(named: 'patchId'),
              channelId: any(named: 'channelId'),
            ),
          ).thenAnswer((_) async => patch);

          await runWithOverrides(
            () => codePushClientWrapper.promotePatch(
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
                  patch: patch,
                  platform: platform,
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
              patchId: any(named: 'patchId'),
              artifactPath: any(named: 'artifactPath'),
              arch: any(named: 'arch'),
              platform: any(named: 'platform'),
              hash: any(named: 'hash'),
            ),
          ).thenAnswer((_) async {});

          await runWithOverrides(
            () => codePushClientWrapper.createPatchArtifacts(
              patch: patch,
              platform: platform,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(() => progress.complete()).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: platform,
              hash: partchArtifactBundle.hash,
            ),
          ).called(1);
        });
      });

      group('publishPatch', () {
        setUp(() {
          when(
            () => codePushClient.createPatch(releaseId: releaseId),
          ).thenAnswer((_) async => patch);
          when(
            () => codePushClient.createPatchArtifact(
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
              platform: platform,
              channelName: channelName,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(
            () => codePushClient.createPatch(releaseId: releaseId),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: platform,
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
              platform: platform,
              channelName: channelName,
              patchArtifactBundles: patchArtifactBundles,
            ),
          );

          verify(
            () => codePushClient.createPatch(releaseId: releaseId),
          ).called(1);
          verify(
            () => codePushClient.createPatchArtifact(
              artifactPath: partchArtifactBundle.path,
              patchId: patchId,
              arch: arch.name,
              platform: platform,
              hash: partchArtifactBundle.hash,
            ),
          ).called(1);
          verify(() => codePushClient.getChannels(appId: appId)).called(1);
          verify(
            () => codePushClient.createChannel(
              appId: appId,
              channel: channelName,
            ),
          ).called(1);
          verify(
            () => codePushClient.promotePatch(
              patchId: patchId,
              channelId: channel.id,
            ),
          ).called(1);
        });
      });
    });
  });
}
