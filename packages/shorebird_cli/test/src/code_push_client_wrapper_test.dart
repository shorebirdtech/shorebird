import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group(CodePushClientWrapper, () {
    Matcher exitsWithCode(ExitCode code) => throwsA(
          isA<ProcessExit>().having(
            (e) => e.exitCode,
            'exitCode',
            code,
          ),
        );

    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;

    late CodePushClientWrapper codePushClientWrapper;

    setUpAll(setExitFunctionForTests);

    tearDownAll(restoreExitFunction);

    setUp(() {
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();

      codePushClientWrapper = CodePushClientWrapper(
        codePushClient: codePushClient,
        logger: logger,
      );

      when(() => logger.progress(any())).thenReturn(progress);
    });

    group('getApp', () {
      const appId = 'test-app-id';
      const app = AppMetadata(appId: appId, displayName: 'Test App');

      test('throws error when fetching apps fails.', () async {
        const error = 'something went wrong';
        when(() => codePushClient.getApps()).thenThrow(error);

        await expectLater(
          () async => codePushClientWrapper.getApp(appId: 'asdf'),
          exitsWithCode(ExitCode.software),
        );
        verify(() => progress.fail(error)).called(1);
      });

      test('throws error when app does not exist', () async {
        when(() => codePushClient.getApps()).thenAnswer((_) async => []);

        await expectLater(
          () async => codePushClientWrapper.getApp(appId: appId),
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

        final result = await codePushClientWrapper.getApp(appId: appId);

        expect(result, app);
        verify(() => progress.complete()).called(1);
      });
    });

    group('maybeGetApp', () {
      const appId = 'test-app-id';
      const app = AppMetadata(appId: appId, displayName: 'Test App');

      test('succeeds if app does not exist and failOnNotFound is false',
          () async {
        when(() => codePushClient.getApps()).thenAnswer((_) async => [app]);

        final result = await codePushClientWrapper.getApp(
          appId: appId,
        );

        expect(result, app);
        verify(() => progress.complete()).called(1);
        verifyNever(() => logger.err(any()));
      });
    });

    group('getChannel', () {});

    group('createChannel', () {});

    group('getRelease', () {
//       test('throws error when fetching releases fails.', () async {
//         const error = 'something went wrong';
//         when(
//           () => codePushClient.getReleases(appId: any(named: 'appId')),
//         ).thenThrow(error);
//         final tempDir = setUpTempDir();
//         final exitCode = await IOOverrides.runZoned(
//           command.run,
//           getCurrentDirectory: () => tempDir,
//         );
//         verify(() => progress.fail(error)).called(1);
//         expect(exitCode, ExitCode.software.code);
//       });

//       test('throws error when release does not exist.', () async {
//         when(
//           () => codePushClient.getReleases(appId: any(named: 'appId')),
//         ).thenAnswer((_) async => []);
//         final tempDir = setUpTempDir();
//         final exitCode = await IOOverrides.runZoned(
//           command.run,
//           getCurrentDirectory: () => tempDir,
//         );
//         verify(
//           () => logger.err(
//             '''
// Release not found: "$version"

// Patches can only be published for existing releases.
// Please create a release using "shorebird release" and try again.
// ''',
//           ),
//         ).called(1);
//         expect(exitCode, ExitCode.software.code);
//       });
    });
  });
}
