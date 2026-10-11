import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/releases/releases_list_command.dart';
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
  group(ReleasesListCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 1,
      appId: appId,
      version: '1.0.0+1',
      flutterRevision: 'abc123',
      flutterVersion: '3.27.0',
      displayName: '1.0.0+1',
      platformStatuses: const {
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
      },
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 16),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late Progress progress;
    late ReleasesListCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(ReleasesListCommand.new)
        ..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults['platform']).thenReturn(null);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => [release]);
    });

    test('has correct name', () {
      expect(command.name, 'list');
    });

    test('has correct description', () {
      expect(command.description, startsWith('List releases for an app.'));
    });

    group('when validation fails', () {
      final exception = ShorebirdNotInitializedException();

      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);
      });

      test('returns the precondition failure exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    group('when --app-id is provided', () {
      setUp(() {
        when(() => argResults['app-id']).thenReturn('explicit-app-id');
      });

      test('fetches releases for the explicit app id', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getReleases(appId: 'explicit-app-id'),
        ).called(1);
      });
    });

    group('when --app-id is not provided', () {
      test('fetches releases using app id from shorebird.yaml', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getReleases(appId: appId),
        ).called(1);
      });
    });

    group('when there are no releases', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
        ).thenAnswer((_) async => []);
      });

      test('prints a message', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info('No releases found.')).called(1);
      });
    });

    group('when --platform filter is provided', () {
      final androidRelease = Release(
        id: 2,
        appId: appId,
        version: '2.0.0',
        flutterRevision: 'def456',
        flutterVersion: '3.27.0',
        displayName: '2.0.0',
        platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
        createdAt: DateTime(2026, 2),
        updatedAt: DateTime(2026, 2, 2),
      );

      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
        ).thenAnswer((_) async => [release, androidRelease]);
        when(() => argResults['platform']).thenReturn('ios');
      });

      test('only shows releases with the given platform', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        // release has ios; androidRelease does not — only one info call
        verify(() => logger.info(any())).called(1);
      });
    });

    group('human-readable output', () {
      test('prints each release with id and version', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            any(that: allOf(contains('1'), contains('1.0.0+1'))),
          ),
        ).called(1);
      });
    });

    group('when API fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in --json mode, emits JSON error envelope', () async {
        final (:exitCode, :json) = await captureJson(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(json['status'], 'error');
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test('emits JSON success with releases list', () async {
        final (:exitCode, :json) = await captureJson(
          () => runJsonMode(command.run),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final data = json['data'] as Map<String, dynamic>;
        expect(data['releases'], isA<List<dynamic>>());
        expect((data['releases'] as List<dynamic>).length, 1);
      });

      test('does not use a progress spinner', () async {
        await captureJson(
          () => runJsonMode(command.run),
        );
        verifyNever(() => logger.progress(any()));
      });
    });
  });
}
