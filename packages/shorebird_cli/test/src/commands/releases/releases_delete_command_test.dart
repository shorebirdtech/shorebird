import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ReleasesDeleteCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0+1';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 42,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'abc123',
      flutterVersion: '3.27.0',
      displayName: releaseVersion,
      platformStatuses: const {
        ReleasePlatform.ios: ReleaseStatus.active,
        ReleasePlatform.android: ReleaseStatus.active,
      },
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 16),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late ReleasesDeleteCommand command;

    R runWithOverrides<R>(
      R Function() body, {
      bool jsonMode = false,
    }) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void verifyNeverDeleted() {
      verifyNever(
        () => codePushClientWrapper.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      );
      verifyNever(
        () => codePushClientWrapper.deleteReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
        ),
      );
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => argResults['platform']).thenReturn(null);
      when(() => argResults['yes']).thenReturn(true);
      when(() => argResults['confirm-name']).thenReturn(null);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.deleteReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(ReleasesDeleteCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'delete');
      expect(
        command.description,
        startsWith(
          'Permanently deletes a release, or one platform of a release.',
        ),
      );
      expect(command.description, contains('every patch'));
    });

    test('--platform only accepts known platforms', () {
      expect(
        command.argParser.options['platform']!.allowed,
        equals(['android', 'ios', 'linux', 'macos', 'windows']),
      );
    });

    group('without --platform', () {
      test('resolves the version to an id and deletes the release', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.maybeGetRelease(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        ).called(1);
        verify(
          () => codePushClientWrapper.deleteRelease(
            appId: appId,
            releaseId: release.id,
          ),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.deleteReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
          ),
        );
        verify(
          () => logger.success('Deleted release "$releaseVersion".'),
        ).called(1);
      });

      test('emits what was deleted under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['data'], {
          'app_id': appId,
          'release_id': release.id,
          'release_version': releaseVersion,
          'release_deleted': true,
          'platforms': ['android', 'ios'],
          'deleted': true,
        });
      });
    });

    group('with --platform', () {
      setUp(() => when(() => argResults['platform']).thenReturn('ios'));

      test('deletes only that platform', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.deleteReleaseArtifacts(
            appId: appId,
            releaseId: release.id,
            platform: ReleasePlatform.ios,
          ),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.deleteRelease(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        );
        verify(
          () => logger.success(
            'Deleted the ios platform of release "$releaseVersion".',
          ),
        ).called(1);
      });

      test('emits what was deleted under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['data'], {
          'app_id': appId,
          'release_id': release.id,
          'release_version': releaseVersion,
          'release_deleted': false,
          'platforms': ['ios'],
          'deleted': true,
        });
      });

      group('when the release does not have that platform', () {
        setUp(() => when(() => argResults['platform']).thenReturn('macos'));

        test('exits with usage and lists the release platforms', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
          verifyNeverDeleted();
          verify(
            () => logger.err(
              'Release "$releaseVersion" has no macos platform to delete.',
            ),
          ).called(1);
          verify(
            () => logger.info('Platforms on this release: android, ios'),
          ).called(1);
        });

        test('emits a usage_error envelope under --json', () async {
          final (:exitCode, :json) = await captureJson(
            () => runWithOverrides(command.run, jsonMode: true),
          );
          expect(exitCode, equals(ExitCode.usage.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], 'usage_error');
          expect(error['hint'], 'Platforms on this release: android, ios');
        });
      });
    });

    group('when the release does not exist', () {
      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => null);
      });

      test('exits with usage and names the list command', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.err(
            'No release with version "$releaseVersion" for app "$appId".',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'Run "shorebird releases list --app-id $appId" to see its '
            'release versions.',
          ),
        ).called(1);
      });

      test('emits a usage_error envelope under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
      });
    });

    group('confirmation', () {
      setUp(() => when(() => argResults['yes']).thenReturn(false));

      test('requires --yes when not interactive', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.err('--yes required when not running interactively'),
        ).called(1);
        verify(
          () => logger.info(
            'Re-run with --yes to delete release $releaseVersion of app '
            '"$appId", including every platform and every patch.',
          ),
        ).called(1);
      });

      test('names only the platform when --platform is set', () async {
        when(() => argResults['platform']).thenReturn('android');
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.info(
            'Re-run with --yes to delete the android platform of release '
            '$releaseVersion of app "$appId".',
          ),
        ).called(1);
      });

      test('emits a usage_error envelope under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(
          error['message'],
          '--yes required when not running interactively',
        );
      });

      group('in a terminal', () {
        setUp(
          () => when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true),
        );

        test('deletes when confirmed', () async {
          when(
            () => logger.confirm(any(), hint: any(named: 'hint')),
          ).thenReturn(true);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.confirm(
              'Delete release $releaseVersion of app "$appId", including '
              'every platform and every patch?',
              hint: any(named: 'hint'),
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.deleteRelease(
              appId: appId,
              releaseId: release.id,
            ),
          ).called(1);
        });

        test('does nothing when declined', () async {
          when(
            () => logger.confirm(any(), hint: any(named: 'hint')),
          ).thenReturn(false);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNeverDeleted();
          verify(() => logger.info('Nothing was deleted.')).called(1);
        });
      });

      group('with the deprecated --confirm-name', () {
        test('deletes when it matches', () async {
          when(() => argResults['confirm-name']).thenReturn(releaseVersion);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.warn(any(that: contains('deprecated'))),
          ).called(1);
        });

        test('refuses when it does not match', () async {
          when(() => argResults['confirm-name']).thenReturn('1.0.0+2');
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
          verifyNeverDeleted();
        });
      });
    });

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('emits a fetch_failed envelope in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        verifyNeverDeleted();
        expect(
          (json['error'] as Map<String, dynamic>)['code'],
          'fetch_failed',
        );
      });
    });

    // The wrapper reports the server's error (e.g. a 403 for a caller without
    // permission to delete releases) and throws ProcessExit.
    group('when the server rejects the delete', () {
      setUp(() {
        when(
          () => codePushClientWrapper.deleteRelease(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
        when(
          () => codePushClientWrapper.deleteReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('exits with software without printing success', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
        verifyNever(() => logger.success(any()));
      });

      test('emits a software_error envelope in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'software_error');
        expect(error['message'], 'Failed to delete release "$releaseVersion".');
      });

      test('names the platform under --platform', () async {
        when(() => argResults['platform']).thenReturn('ios');
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(
          error['message'],
          'Failed to delete the ios platform of release "$releaseVersion".',
        );
      });
    });
  });
}
