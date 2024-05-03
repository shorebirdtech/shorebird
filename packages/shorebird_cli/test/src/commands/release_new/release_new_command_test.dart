import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/aar_releaser.dart';
import 'package:shorebird_cli/src/commands/release_new/android_releaser.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/commands/release_new/releaser.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(ReleaseNewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const releaseVersion = '1.2.3+1';
    const postReleaseInstructions = 'Make a patch!';
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
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Logger logger;
    late Progress progress;
    late Releaser releaser;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    late ReleaseNewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(release);
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockLogger();
      progress = MockProgress();
      releaser = MockReleaser();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => argResults['platform']).thenReturn(['android']);
      when(() => argResults.wasParsed(any())).thenReturn(true);

      when(() => codePushClientWrapper.getApp(appId: any(named: 'appId')))
          .thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async {});

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);

      when(() => releaser.validatePreconditions()).thenAnswer((_) async => {});
      when(() => releaser.validateArgs()).thenAnswer((_) async => {});
      when(() => releaser.buildReleaseArtifacts())
          .thenAnswer((_) async => File(''));
      when(
        () => releaser.getReleaseVersion(
          releaseArtifactRoot: any(named: 'releaseArtifactRoot'),
        ),
      ).thenAnswer((_) async => releaseVersion);
      when(
        () => releaser.uploadReleaseArtifacts(
          release: any(named: 'release'),
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => {});
      when(() => releaser.postReleaseInstructions)
          .thenReturn(postReleaseInstructions);
      when(() => releaser.releaseType).thenReturn(ReleaseType.android);
      when(() => releaser.releaseMetadata)
          .thenReturn(UpdateReleaseMetadata.forTest());

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
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
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});

      command = ReleaseNewCommand(resolveReleaser: (_) => releaser)
        ..testArgResults = argResults;
    });

    group('getReleaser', () {
      test('maps the correct platform to the releaser', () async {
        expect(
          command.getReleaser(ReleaseType.android),
          isA<AndroidReleaser>(),
        );
        expect(
          command.getReleaser(ReleaseType.aar),
          isA<AarReleaser>(),
        );
        expect(
          () => command.getReleaser(ReleaseType.ios),
          throwsA(isA<UnimplementedError>()),
        );
        expect(
          () => command.getReleaser(ReleaseType.iosFramework),
          throwsA(isA<UnimplementedError>()),
        );
      });
    });

    test('asdf', () async {
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.success.code));
    });

    group('when flutter-version is provided', () {
      const flutterVersion = '3.16.3';
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn(flutterVersion);
      });

      group('when unable to determine flutter revision', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err(
              '''
Unable to determine revision for Flutter version: $flutterVersion.
$exception''',
            ),
          ).called(1);
        });
      });

      group('when flutter version is not supported', () {
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => null);
        });

        test('exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(command.run),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err(
              any(that: contains('Version $flutterVersion not found.')),
            ),
          ).called(1);
        });
      });

      group('when flutter version is supported', () {
        const revision = '771d07b2cf';
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => revision);
        });

        test(
            'uses specified flutter version to build '
            'and reverts to original flutter version', () async {
          when(releaser.buildReleaseArtifacts).thenAnswer((_) async {
            // Ensure we're using the correct flutter version.
            expect(shorebirdEnv.flutterRevision, equals(revision));
            return File('');
          });

          await runWithOverrides(command.run);

          verify(() => shorebirdFlutter.installRevision(revision: revision))
              .called(1);
        });

        group('when flutter version install fails', () {
          setUp(() {
            when(
              () => shorebirdFlutter.installRevision(
                revision: any(named: 'revision'),
              ),
            ).thenThrow(Exception('oops'));
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(command.run),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => shorebirdFlutter.installRevision(revision: revision),
            ).called(1);
          });
        });
      });
    });
  });
}
